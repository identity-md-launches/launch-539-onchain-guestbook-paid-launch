// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract ContractSigner {
    function sign(LaunchToken token, Guestbook book, string calldata message) external returns (uint256) {
        token.approve(address(book), 10 ether);
        return book.sign(message);
    }
}

contract GuestbookTest is Test {
    LaunchToken private token;
    Guestbook private book;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    event EntrySigned(uint256 indexed index, address indexed signer, string message, uint256 timestamp);

    function setUp() public {
        token = new LaunchToken();
        book = new Guestbook(address(token));
        token.transfer(ALICE, 100 ether);
        token.transfer(BOB, 50 ether);
    }

    function test_initialConfiguration() public view {
        assertEq(address(book.token()), address(token));
        assertEq(book.SIGNING_COST(), 10 ether);
        assertEq(book.MAX_MESSAGE_BYTES(), 280);
        assertEq(book.BURN_ADDRESS(), DEAD);
        assertEq(book.entryCount(), 0);
    }

    function test_signBurnsExactlyTenAndStoresEntryAndEvent() public {
        vm.warp(1_800_123_456);
        _approve(ALICE, 10 ether);
        vm.expectEmit(true, true, false, true, address(book));
        emit EntrySigned(0, ALICE, "Hello, chain!", block.timestamp);
        vm.prank(ALICE);
        assertEq(book.sign("Hello, chain!"), 0);

        _assertEntry(0, ALICE, "Hello, chain!", 1_800_123_456);
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(ALICE), 90 ether);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.balanceOf(address(book)), 0);
        assertEq(token.allowance(ALICE, address(book)), 0);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function test_multipleSignersAndDuplicateMessagesHaveStableIndexes() public {
        _approve(ALICE, 20 ether);
        _approve(BOB, 10 ether);
        vm.warp(123);
        vm.prank(ALICE);
        assertEq(book.sign("same message"), 0);
        vm.warp(127);
        vm.prank(BOB);
        assertEq(book.sign("another signer"), 1);
        // Repeated signatures, even in the same block, are separate paid entries.
        vm.prank(ALICE);
        assertEq(book.sign("same message"), 2);

        _assertEntry(0, ALICE, "same message", 123);
        _assertEntry(1, BOB, "another signer", 127);
        _assertEntry(2, ALICE, "same message", 127);
        assertEq(book.entryCount(), 3);
        assertEq(token.balanceOf(ALICE), 80 ether);
        assertEq(token.balanceOf(BOB), 40 ether);
        assertEq(token.balanceOf(DEAD), 30 ether);
    }

    function test_emptyMessageIsAllowedAndCharged() public {
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        book.sign("");
        _assertEntry(0, ALICE, "", block.timestamp);
        assertEq(token.balanceOf(DEAD), 10 ether);
    }

    function test_exactly280BytesAllowed() public {
        string memory message = string(new bytes(280));
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        book.sign(message);
        _assertEntry(0, ALICE, message, block.timestamp);
        assertEq(token.balanceOf(DEAD), 10 ether);
    }

    function test_multibyteTextIsLimitedByBytes() public {
        bytes memory message;
        for (uint256 i; i < 70; ++i) {
            message = bytes.concat(message, hex"f09f918b"); // UTF-8 waving hand: four bytes.
        }
        _approve(ALICE, 20 ether);
        vm.prank(ALICE);
        book.sign(string(message));
        _assertEntry(0, ALICE, string(message), block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, 284));
        vm.prank(ALICE);
        book.sign(string(bytes.concat(message, hex"f09f918b")));
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.allowance(ALICE, address(book)), 10 ether);
    }

    function test_281BytesRevertsWithoutChangingPriorEntryOrPayment() public {
        _approve(ALICE, 20 ether);
        vm.prank(ALICE);
        book.sign("first");
        uint256 timestamp = vm.getBlockTimestamp();
        vm.warp(timestamp + 10);
        vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, 281));
        vm.prank(ALICE);
        book.sign(string(new bytes(281)));
        _assertEntry(0, ALICE, "first", timestamp);
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(ALICE), 90 ether);
        assertEq(token.balanceOf(DEAD), 10 ether);
        assertEq(token.allowance(ALICE, address(book)), 10 ether);
    }

    function testFuzz_messageBytesAndTimestampRoundTrip(bytes memory message, uint64 timestamp) public {
        _approve(ALICE, 10 ether);
        vm.warp(timestamp);
        if (message.length > 280) {
            vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, message.length));
            vm.prank(ALICE);
            book.sign(string(message));
            _assertUnpaid();
        } else {
            vm.prank(ALICE);
            book.sign(string(message));
            _assertEntry(0, ALICE, string(message), timestamp);
            assertEq(book.entryCount(), 1);
            assertEq(token.balanceOf(DEAD), 10 ether);
        }
    }

    function test_missingApprovalRevertsAndCanBeRetried() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(book), 0, 10 ether)
        );
        vm.prank(ALICE);
        book.sign("not approved");
        _assertUnpaid();
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        assertEq(book.sign("approved now"), 0);
    }

    function test_insufficientAllowanceReverts() public {
        _approve(ALICE, 10 ether - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(book), 10 ether - 1, 10 ether
            )
        );
        vm.prank(ALICE);
        book.sign("short by one");
        _assertUnpaid();
        assertEq(token.allowance(ALICE, address(book)), 10 ether - 1);
    }

    function test_insufficientBalanceRevertsAndRestoresAllowance() public {
        vm.prank(ALICE);
        token.transfer(BOB, 90 ether + 1);
        _approve(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether - 1, 10 ether)
        );
        vm.prank(ALICE);
        book.sign("short balance");
        assertEq(book.entryCount(), 0);
        assertEq(token.balanceOf(ALICE), 10 ether - 1);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(token.allowance(ALICE, address(book)), 10 ether);
    }

    function test_exactBalanceCanSignOnceOnly() public {
        vm.prank(ALICE);
        token.transfer(BOB, 90 ether);
        _approve(ALICE, 20 ether);
        vm.prank(ALICE);
        book.sign("last ten");
        assertEq(token.balanceOf(ALICE), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(ALICE);
        book.sign("no tokens left");
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(DEAD), 10 ether);
    }

    function test_callerCannotSpendAnotherSignersApproval() public {
        _approve(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(book), 0, 10 ether)
        );
        vm.prank(BOB);
        book.sign("Alice approved, Bob did not");
        _assertUnpaid();
        assertEq(token.allowance(ALICE, address(book)), 10 ether);
        assertEq(token.balanceOf(BOB), 50 ether);
    }

    function test_contractSignerIsRecordedAsCaller() public {
        ContractSigner signer = new ContractSigner();
        token.transfer(address(signer), 10 ether);
        signer.sign(token, book, "contract account");
        _assertEntry(0, address(signer), "contract account", block.timestamp);
        assertEq(token.balanceOf(address(signer)), 0);
        assertEq(token.balanceOf(DEAD), 10 ether);
    }

    function test_donationsDoNotCreateEntriesOrDiscountPayment() public {
        token.transfer(DEAD, 5 ether);
        token.transfer(address(book), 3 ether);
        assertEq(book.entryCount(), 0);
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        book.sign("still costs ten");
        assertEq(book.entryCount(), 1);
        assertEq(token.balanceOf(ALICE), 90 ether);
        assertEq(token.balanceOf(DEAD), 15 ether);
        assertEq(token.balanceOf(address(book)), 3 ether);
    }

    function test_nonexistentIndexesRevert() public {
        vm.expectRevert();
        book.entries(0);
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        book.sign("only one");
        vm.expectRevert();
        book.entries(1);
        vm.expectRevert();
        book.entries(type(uint256).max);
    }

    function test_constructorRejectsZeroAddressAndEOA() public {
        vm.expectRevert(Guestbook.InvalidToken.selector);
        new Guestbook(address(0));
        vm.expectRevert(Guestbook.InvalidToken.selector);
        new Guestbook(ALICE);
    }

    function test_signRejectsNativeCurrency() public {
        vm.deal(ALICE, 1 ether);
        _approve(ALICE, 10 ether);
        vm.prank(ALICE);
        (bool success,) = address(book).call{value: 1}(abi.encodeCall(book.sign, ("with ETH")));
        assertFalse(success);
        assertEq(address(book).balance, 0);
        assertEq(ALICE.balance, 1 ether);
        _assertUnpaid();
    }

    function _approve(address account, uint256 amount) private {
        vm.prank(account);
        token.approve(address(book), amount);
    }

    function _assertEntry(uint256 index, address signer, string memory message, uint256 timestamp) private view {
        (address actualSigner, string memory actualMessage, uint256 actualTimestamp) = book.entries(index);
        assertEq(actualSigner, signer);
        assertEq(actualMessage, message);
        assertEq(actualTimestamp, timestamp);
    }

    function _assertUnpaid() private view {
        assertEq(book.entryCount(), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(token.balanceOf(address(book)), 0);
    }
}
