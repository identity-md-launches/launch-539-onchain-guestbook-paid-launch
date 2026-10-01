// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Guestbook} from "../src/Guestbook.sol";
import {PaymentToken} from "./mocks/PaymentToken.sol";

contract GuestbookAdversarialTest is Test {
    PaymentToken private token;
    Guestbook private book;
    address private constant ALICE = address(0xA11CE);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new PaymentToken(18);
        book = new Guestbook(address(token));
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(address(book), 20 ether);
    }

    function test_falseReturnRevertsEvenAfterTokenMovedFunds() public {
        token.setMode(PaymentToken.Mode.ReturnFalse);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        vm.prank(ALICE);
        book.sign("failed payment");
        _assertRolledBack();
        _assertCanRetry();
    }

    function test_revertingPaymentIsAtomic() public {
        token.setMode(PaymentToken.Mode.RevertPayment);
        vm.expectRevert(PaymentToken.PaymentReverted.selector);
        vm.prank(ALICE);
        book.sign("reverting payment");
        _assertRolledBack();
        _assertCanRetry();
    }

    function test_feeOnTransferRevertsAndRestoresAllBalances() public {
        token.setMode(PaymentToken.Mode.Fee);
        vm.expectRevert(Guestbook.IncorrectBurnAmount.selector);
        vm.prank(ALICE);
        book.sign("underpaid by one unit");
        _assertRolledBack();
        assertEq(token.balanceOf(address(token)), 0);
        _assertCanRetry();
    }

    function test_successWithoutMovementIsRejectedEvenWithExistingBurns() public {
        token.transfer(DEAD, 10 ether);
        token.setMode(PaymentToken.Mode.NoMovement);
        vm.expectRevert(Guestbook.IncorrectBurnAmount.selector);
        vm.prank(ALICE);
        book.sign("no actual payment");
        assertEq(book.entryCount(), 0);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.allowance(ALICE, address(book)), 20 ether);
    }

    function test_safeTransferAcceptsEmptyReturnDataWithExactPayment() public {
        token.setMode(PaymentToken.Mode.ReturnNothing);
        vm.prank(ALICE);
        book.sign("paid with no return data");
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.balanceOf(ALICE), 90 ether);
    }

    function test_caughtReentryCannotAppendAnUnpaidEntry() public {
        token.setMode(PaymentToken.Mode.CatchReentry);
        vm.prank(ALICE);
        assertEq(book.sign("outer entry"), 0);
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackError(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(book.entryCount(), 1);
        (address signer, string memory message,) = book.entries(0);
        assertEq(signer, ALICE);
        assertEq(message, "outer entry");
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.balanceOf(ALICE), 90 ether);
    }

    function test_bubbledReentryRollsBackPaymentAndDoesNotLockBook() public {
        token.setMode(PaymentToken.Mode.BubbleReentry);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        vm.prank(ALICE);
        book.sign("outer entry");
        _assertRolledBack();
        _assertCanRetry();
    }

    function test_constructorRejectsWrongDecimals() public {
        PaymentToken sixDecimals = new PaymentToken(6);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.UnsupportedDecimals.selector, uint8(6)));
        new Guestbook(address(sixDecimals));
    }

    function _assertRolledBack() private view {
        assertEq(book.entryCount(), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(token.balanceOf(address(book)), 0);
        assertEq(token.allowance(ALICE, address(book)), 20 ether);
    }

    function _assertCanRetry() private {
        token.setMode(PaymentToken.Mode.Normal);
        vm.prank(ALICE);
        assertEq(book.sign("retry"), 0);
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(DEAD), 10 ether);
    }
}
