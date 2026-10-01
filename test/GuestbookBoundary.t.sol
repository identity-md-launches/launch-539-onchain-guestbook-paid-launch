// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {Guestbook} from "src/Guestbook.sol";

contract GuestbookBatchSigner {
    function signTwice(LaunchToken token, Guestbook book, string calldata first, string calldata second)
        external
        returns (uint256 firstIndex, uint256 secondIndex)
    {
        token.approve(address(book), 20 ether);
        firstIndex = book.sign(first);
        secondIndex = book.sign(second);
    }
}

contract GuestbookBoundaryTest is Test {
    LaunchToken private token;
    Guestbook private book;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new LaunchToken();
        book = new Guestbook(address(token));
        token.transfer(ALICE, 100 ether);
        token.transfer(BOB, 100 ether);
    }

    function test_storageLengthBoundariesRemainIndependentAfterLaterAppends() public {
        uint256[10] memory lengths = [uint256(0), 1, 30, 31, 32, 33, 63, 64, 279, 280];
        _approve(ALICE, 50 ether);
        _approve(BOB, 50 ether);

        for (uint256 i; i < lengths.length; ++i) {
            address signer = i % 2 == 0 ? ALICE : BOB;
            vm.warp(1_800_000_000 + i);
            vm.prank(signer);
            assertEq(book.sign(_message(lengths[i], bytes32(i + 1))), i);
        }

        // Read backwards after every append so that corruption of older dynamic strings is visible.
        for (uint256 remaining = lengths.length; remaining != 0; --remaining) {
            uint256 i = remaining - 1;
            _assertEntry(i, i % 2 == 0 ? ALICE : BOB, _message(lengths[i], bytes32(i + 1)), 1_800_000_000 + i);
        }
        assertEq(book.entryCount(), lengths.length);
        assertEq(token.balanceOf(ALICE), 50 ether);
        assertEq(token.balanceOf(BOB), 50 ether);
        assertEq(token.balanceOf(DEAD), 100 ether);
        assertEq(token.balanceOf(address(book)), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_readsRespectThePopulatedIndexRange(uint8 countSeed, uint256 indexSeed, bytes32 contentSeed)
        public
    {
        uint256 count = bound(uint256(countSeed), 1, 8);
        _approve(ALICE, count * 10 ether);
        for (uint256 i; i < count; ++i) {
            vm.warp(10_000 + i);
            vm.prank(ALICE);
            assertEq(book.sign(_message(31 + i, contentSeed)), i);
        }

        uint256 validIndex = indexSeed % count;
        _assertEntry(validIndex, ALICE, _message(31 + validIndex, contentSeed), 10_000 + validIndex);

        uint256 invalidIndex = bound(indexSeed, count, type(uint256).max);
        vm.expectRevert();
        book.entries(invalidIndex);

        assertEq(book.entryCount(), count);
        assertEq(token.balanceOf(DEAD), count * 10 ether);
        assertEq(token.balanceOf(ALICE), 100 ether - count * 10 ether);
        _assertEntry(validIndex, ALICE, _message(31 + validIndex, contentSeed), 10_000 + validIndex);
    }

    function test_revokingApprovalAfterSigningPreservesHistoryAndAllowsRetry() public {
        _approve(ALICE, type(uint256).max);
        vm.warp(1234);
        vm.prank(ALICE);
        assertEq(book.sign("before revocation"), 0);
        assertEq(token.allowance(ALICE, address(book)), type(uint256).max);

        _approve(ALICE, 0);
        vm.warp(1235);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(book), 0, 10 ether)
        );
        vm.prank(ALICE);
        book.sign("revoked");
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(ALICE), 90 ether);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.allowance(ALICE, address(book)), 0);
        _assertEntry(0, ALICE, "before revocation", 1234);

        _approve(ALICE, 10 ether);
        vm.warp(1236);
        vm.prank(ALICE);
        assertEq(book.sign("after renewal"), 1);
        _assertEntry(0, ALICE, "before revocation", 1234);
        _assertEntry(1, ALICE, "after renewal", 1236);
        assertEq(book.entryCount(), 2);
        assertEq(token.balanceOf(ALICE), 80 ether);
        assertEq(token.balanceOf(DEAD), 20 ether);
        assertEq(token.allowance(ALICE, address(book)), 0);
    }

    function test_failedBatchRollsBackItsEarlierSignatureAndPayment() public {
        _approve(ALICE, 10 ether);
        vm.warp(2000);
        vm.prank(ALICE);
        book.sign("already committed");

        GuestbookBatchSigner batchSigner = new GuestbookBatchSigner();
        token.transfer(address(batchSigner), 20 ether);
        vm.warp(2001);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, 281));
        batchSigner.signTwice(token, book, "must roll back", _message(281, bytes32(uint256(7))));

        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(address(batchSigner)), 20 ether);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.balanceOf(address(book)), 0);
        assertEq(token.allowance(address(batchSigner), address(book)), 0);
        _assertEntry(0, ALICE, "already committed", 2000);
        vm.expectRevert();
        book.entries(1);

        vm.warp(2002);
        (uint256 firstIndex, uint256 secondIndex) = batchSigner.signTwice(token, book, "first", "second");
        assertEq(firstIndex, 1);
        assertEq(secondIndex, 2);
        _assertEntry(0, ALICE, "already committed", 2000);
        _assertEntry(1, address(batchSigner), "first", 2002);
        _assertEntry(2, address(batchSigner), "second", 2002);
        assertEq(book.entryCount(), 3);
        assertEq(token.balanceOf(address(batchSigner)), 0);
        assertEq(token.balanceOf(DEAD), 30 ether);
        assertEq(token.allowance(address(batchSigner), address(book)), 0);
    }

    function _approve(address signer, uint256 amount) private {
        vm.prank(signer);
        token.approve(address(book), amount);
    }

    function _assertEntry(uint256 index, address signer, string memory message, uint256 timestamp) private view {
        (address actualSigner, string memory actualMessage, uint256 actualTimestamp) = book.entries(index);
        assertEq(actualSigner, signer);
        assertEq(bytes(actualMessage), bytes(message));
        assertEq(actualTimestamp, timestamp);
    }

    function _message(uint256 length, bytes32 seed) private pure returns (string memory) {
        bytes memory message = new bytes(length);
        for (uint256 i; i < length; ++i) {
            message[i] = bytes1(uint8(i)) ^ seed[i % 32];
        }
        return string(message);
    }
}
