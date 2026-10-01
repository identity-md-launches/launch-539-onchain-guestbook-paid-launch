// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenBoundaryTest is Test {
    LaunchToken private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new LaunchToken();
    }

    function testFuzz_failedDelegatedPaymentRestoresFiniteAllowance(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);

        assertEq(token.allowance(ALICE, SPENDER), amount, "failed payment consumed allowance");
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_spenderCannotExceedFiniteApproval(uint256 allowanceSeed) public {
        uint256 allowance = bound(allowanceSeed, 0, SUPPLY - 1);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(SPENDER, allowance);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, allowance + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, allowance + 1);

        assertEq(token.allowance(ALICE, SPENDER), allowance);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementAndRevocation(uint256 initial, uint256 replacement) public {
        token.transfer(ALICE, 1);
        vm.startPrank(ALICE);
        assertTrue(token.approve(SPENDER, initial));
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement, "approval should replace the old amount");
        assertTrue(token.approve(SPENDER, 0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);

        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_invalidDelegatedRecipientRestoresAllowanceAndBalance() public {
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 1);

        assertEq(token.allowance(ALICE, SPENDER), 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_approvalCannotBeBorrowedByAnotherSpender() public {
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);

        assertEq(token.allowance(ALICE, SPENDER), 1);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_zeroTransfersNeedNeitherBalanceNorAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));

        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyCanMakeADelegatedRoundTrip() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), SUPPLY));

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutArithmeticPanic() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
