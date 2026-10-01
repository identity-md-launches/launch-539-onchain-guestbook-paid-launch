// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_supplyAndMetadata() public view {
        assertEq(token.name(), "Guestbook Token");
        assertEq(token.symbol(), "GUEST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function testFuzz_transferMovesExactAmount(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvedTransferConsumesAllowance() public {
        token.transfer(ALICE, 20 ether);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 12 ether));
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 10 ether));
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 10 ether);
        assertEq(token.allowance(ALICE, BOB), 2 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferCannotExceedBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        token.transfer(address(this), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_infiniteAllowanceHasStandardERC20Semantics() public {
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1 ether);
        assertEq(token.allowance(address(this), BOB), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    function test_noAdministrativeEntryPointsForDeployerOrStranger() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1 ether));
            (bool deployerSucceeded,) = address(token).call(data);
            assertFalse(deployerSucceeded);
            vm.prank(ALICE);
            (bool strangerSucceeded,) = address(token).call(data);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
