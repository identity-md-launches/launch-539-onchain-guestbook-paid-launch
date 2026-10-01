// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {Guestbook} from "src/Guestbook.sol";

/// @dev The model is funded with real transfers. No storage edits or token balance cheatcodes.
///      Expected balances, allowances and history come from inputs, never from observed outputs.
contract GuestbookStatefulHandler is Test {
    uint256 private constant COST = 10 ether;
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    LaunchToken private immutable token;
    Guestbook private immutable book;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE), address(0xD00D)];

    mapping(address => uint256) public expectedBalance;
    mapping(address => uint256) public expectedAllowance;
    uint256 public paidEntries;
    uint256 public donatedToBook;
    uint256 public donatedToDead;
    uint256 public rejectedMessages;
    uint256 public rejectedAllowances;
    uint256 public rejectedBalances;
    bytes32 public historyHash;

    constructor(LaunchToken token_, Guestbook book_) {
        token = token_;
        book = book_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 100 ether;
        }
        expectedBalance[address(this)] = SUPPLY - actors.length * 100 ether;
    }

    function approve(uint8 actorSeed, uint256 amountSeed, bool unlimited) external {
        _approve(_actor(actorSeed), unlimited ? type(uint256).max : bound(amountSeed, 0, 50 ether));
    }

    /// @dev Destinations 4 and 5 are unsolicited donations, not signing payments.
    function transfer(uint8 actorSeed, uint8 destinationSeed, uint256 amountSeed) external {
        address from = _actor(actorSeed);
        uint256 destination = uint256(destinationSeed) % 6;
        address to = destination < 4 ? actors[destination] : destination == 4 ? address(book) : DEAD;
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        _transfer(from, to, amount);
        if (to == address(book)) donatedToBook += amount;
        if (to == DEAD) donatedToDead += amount;
    }

    /// @dev Crucially, this action does not repair the caller's allowance or balance.
    function sign(uint8 actorSeed, uint256 lengthSeed, bytes32 content, uint32 elapsed) external {
        _advance(elapsed);
        _sign(_actor(actorSeed), _message(bound(lengthSeed, 0, 320), content));
    }

    /// @dev Ensures the campaign keeps exercising successful payments after draining/revoking calls.
    function fundedSign(uint8 actorSeed, uint256 lengthSeed, bytes32 content, bool unlimited, uint32 elapsed) external {
        address actor = _actor(actorSeed);
        if (expectedBalance[actor] < COST) {
            _transfer(address(this), actor, COST - expectedBalance[actor]);
        }
        _approve(actor, unlimited ? type(uint256).max : COST);
        _advance(elapsed);
        _sign(actor, _message(bound(lengthSeed, 0, 280), content));
    }

    function signOversized(uint8 actorSeed, uint256 lengthSeed) external {
        _sign(_actor(actorSeed), string(new bytes(bound(lengthSeed, 281, 4096))));
    }

    /// @dev A valid approval is not a reservation: a user can spend all tokens before signing.
    function spendThenSign(uint8 actorSeed) external {
        address actor = _actor(actorSeed);
        address receiver = actors[(uint256(actorSeed) % actors.length + 1) % actors.length];
        _approve(actor, COST);
        _transfer(actor, receiver, expectedBalance[actor]);
        _sign(actor, "spent before signing");
    }

    function _sign(address actor, string memory message) private {
        uint256 timestamp = vm.getBlockTimestamp();
        uint256 length = bytes(message).length;
        bytes memory expectedError;
        if (length > 280) {
            expectedError = abi.encodeWithSelector(Guestbook.MessageTooLong.selector, length);
            ++rejectedMessages;
        } else if (expectedAllowance[actor] < COST) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(book), expectedAllowance[actor], COST
            );
            ++rejectedAllowances;
        } else if (expectedBalance[actor] < COST) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actor, expectedBalance[actor], COST
            );
            ++rejectedBalances;
        }

        vm.prank(actor);
        (bool success, bytes memory result) = address(book).call(abi.encodeCall(book.sign, (message)));
        if (expectedError.length != 0) {
            assertFalse(success, "invalid signing unexpectedly succeeded");
            assertEq(result, expectedError, "unexpected signing error");
            // Model stays unchanged: the invariants check payment, allowance and history rollback.
            return;
        }

        assertTrue(success, "funded approved signing must succeed");
        assertEq(abi.decode(result, (uint256)), paidEntries, "returned index must be append-only");
        expectedBalance[actor] -= COST;
        expectedBalance[DEAD] += COST;
        if (expectedAllowance[actor] != type(uint256).max) expectedAllowance[actor] -= COST;
        historyHash = keccak256(abi.encode(historyHash, actor, message, timestamp));
        ++paidEntries;
    }

    function _approve(address actor, uint256 amount) private {
        vm.prank(actor);
        assertTrue(token.approve(address(book), amount));
        expectedAllowance[actor] = amount;
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _actor(uint8 seed) private view returns (address) {
        return actors[uint256(seed) % actors.length];
    }

    function _advance(uint32 elapsed) private {
        vm.warp(vm.getBlockTimestamp() + bound(uint256(elapsed), 0, 30 days));
    }

    function _message(uint256 length, bytes32 content) private pure returns (string memory) {
        bytes memory message = new bytes(length);
        for (uint256 i; i < length; ++i) {
            message[i] = content[i % 32];
        }
        return string(message);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract GuestbookStatefulTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    LaunchToken private token;
    Guestbook private book;
    GuestbookStatefulHandler private handler;

    function setUp() public {
        token = new LaunchToken();
        book = new Guestbook(address(token));
        handler = new GuestbookStatefulHandler(token, book);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 100 ether);
        }
        token.transfer(address(handler), SUPPLY - 400 ether);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = GuestbookStatefulHandler.approve.selector;
        selectors[1] = GuestbookStatefulHandler.transfer.selector;
        selectors[2] = GuestbookStatefulHandler.sign.selector;
        selectors[3] = GuestbookStatefulHandler.fundedSign.selector;
        selectors[4] = GuestbookStatefulHandler.signOversized.selector;
        selectors[5] = GuestbookStatefulHandler.spendThenSign.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_balancesAllowancesAndSupplyMatchIndependentModel() public view {
        uint256 accounted = _checkBalance(address(handler)) + _checkBalance(address(book)) + _checkBalance(DEAD);
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            accounted += _checkBalance(actor);
            assertEq(token.allowance(actor, address(book)), handler.expectedAllowance(actor), "allowance mismatch");
        }
        assertEq(accounted, SUPPLY, "tokens lost or created");
        assertEq(token.totalSupply(), SUPPLY, "dead-address transfers must not reduce totalSupply");
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_onlyPaidCallsAppendAndAllEarlierEntriesStayIntact() public view {
        uint256 count = handler.paidEntries();
        assertEq(book.entryCount(), count);
        assertEq(token.balanceOf(DEAD), count * 10 ether + handler.donatedToDead());
        assertEq(token.balanceOf(address(book)), handler.donatedToBook(), "signing retained or spent donated tokens");

        bytes32 historyHash;
        for (uint256 i; i < count; ++i) {
            (address signer, string memory message, uint256 timestamp) = book.entries(i);
            assertLe(bytes(message).length, 280);
            historyHash = keccak256(abi.encode(historyHash, signer, message, timestamp));
        }
        assertEq(historyHash, handler.historyHash(), "recorded signer, bytes or timestamp changed");
    }

    /// @dev Pin every handler and failure branch so a misconfigured/vacuous campaign cannot suffice.
    function test_mixedSequenceExercisesFailuresDonationsAndRecovery() public {
        handler.approve(0, 20 ether, false);
        handler.sign(0, 32, bytes32(uint256(1)), 1);
        _assertModel();

        handler.transfer(0, 5, 7);
        handler.transfer(1, 4, 3);
        handler.signOversized(1, 281);
        _assertModel();

        handler.approve(0, 0, false);
        handler.sign(0, 0, bytes32(0), 0);
        _assertModel();

        handler.spendThenSign(1);
        _assertModel();
        handler.fundedSign(1, 280, bytes32(type(uint256).max), true, 1);
        _assertModel();
        handler.fundedSign(0, 1, bytes32(uint256(2)), false, 0);
        _assertModel();

        assertEq(handler.paidEntries(), 3);
        assertEq(handler.rejectedMessages(), 1);
        assertEq(handler.rejectedAllowances(), 1);
        assertEq(handler.rejectedBalances(), 1);
        assertEq(handler.donatedToBook(), 3);
        assertEq(handler.donatedToDead(), 7);
        assertEq(token.allowance(handler.actors(1), address(book)), type(uint256).max);
    }

    function _assertModel() private view {
        invariant_balancesAllowancesAndSupplyMatchIndependentModel();
        invariant_onlyPaidCallsAppendAndAllEarlierEntriesStayIntact();
    }

    function _checkBalance(address account) private view returns (uint256 balance) {
        balance = token.balanceOf(account);
        assertEq(balance, handler.expectedBalance(account), "balance mismatch");
    }
}
