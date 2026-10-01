// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract GuestbookHandler is Test {
    LaunchToken private immutable token;
    Guestbook private immutable book;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE)];
    uint256 public paidEntries;
    mapping(address => uint256) public entriesBySigner;
    bytes32 public historyHash;

    constructor(LaunchToken token_, Guestbook book_) {
        token = token_;
        book = book_;
    }

    function sign(uint8 actorSeed, string memory message, uint32 elapsed) external {
        address actor = actors[uint256(actorSeed) % actors.length];
        uint256 timestamp = vm.getBlockTimestamp() + elapsed;
        vm.warp(timestamp);
        vm.prank(actor);
        token.approve(address(book), 10 ether);
        if (bytes(message).length > 280) {
            vm.expectRevert(abi.encodeWithSelector(Guestbook.MessageTooLong.selector, bytes(message).length));
            vm.prank(actor);
            book.sign(message);
            return;
        }

        vm.prank(actor);
        assertEq(book.sign(message), paidEntries);
        historyHash = keccak256(abi.encode(historyHash, actor, message, timestamp));
        ++paidEntries;
        ++entriesBySigner[actor];
    }
}

contract GuestbookInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    Guestbook private book;
    GuestbookHandler private handler;
    uint256 private constant INITIAL_BALANCE = 100_000 ether;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new LaunchToken();
        book = new Guestbook(address(token));
        handler = new GuestbookHandler(token, book);
        for (uint256 i; i < 3; ++i) {
            token.transfer(handler.actors(i), INITIAL_BALANCE);
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = GuestbookHandler.sign.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_everyEntryIsPaidAndTokensAreConserved() public view {
        uint256 count = handler.paidEntries();
        assertEq(book.entryCount(), count);
        assertEq(token.balanceOf(DEAD), count * 10 ether);
        assertEq(token.balanceOf(address(book)), 0);
        uint256 accounted = token.balanceOf(address(this)) + token.balanceOf(DEAD);
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, INITIAL_BALANCE - handler.entriesBySigner(actor) * 10 ether);
            accounted += balance;
        }
        assertEq(accounted, 1_000_000_000 ether);
        assertEq(token.totalSupply(), accounted);
    }

    function invariant_allHistoricalEntriesRemainIntact() public view {
        bytes32 historyHash;
        for (uint256 i; i < book.entryCount(); ++i) {
            (address signer, string memory message, uint256 timestamp) = book.entries(i);
            historyHash = keccak256(abi.encode(historyHash, signer, message, timestamp));
        }
        assertEq(historyHash, handler.historyHash());
    }
}
