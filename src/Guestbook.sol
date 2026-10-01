// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice An append-only guestbook charging ten launch tokens per entry.
/// @dev Deploy with this project's LaunchToken. No owner, initialization or withdrawal hooks.
contract Guestbook is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant SIGNING_COST = 10 * 10 ** 18;
    uint256 public constant MAX_MESSAGE_BYTES = 280;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable token;

    struct Entry {
        address signer;
        string message;
        uint256 timestamp;
    }

    /// @notice Read an entry by its zero-based index; nonexistent indexes revert.
    Entry[] public entries;

    error InvalidToken();
    error UnsupportedDecimals(uint8 decimals);
    error MessageTooLong(uint256 length);
    error IncorrectBurnAmount();

    event EntrySigned(uint256 indexed index, address indexed signer, string message, uint256 timestamp);

    /// @param token_ The deployed LaunchToken address ($token in the launch manifest).
    constructor(address token_) {
        if (token_.code.length == 0) revert InvalidToken();
        uint8 decimals = IERC20Metadata(token_).decimals();
        if (decimals != 18) revert UnsupportedDecimals(decimals);
        token = IERC20(token_);
    }

    /// @notice Pay ten tokens and append a message of at most 280 bytes, including an empty message.
    /// @dev Caller must approve this contract first. A failed payment rolls back the entire call.
    ///      Burning means transferring to BURN_ADDRESS, without reducing ERC-20 totalSupply.
    /// @return index The zero-based index of the appended entry.
    function sign(string calldata message) external nonReentrant returns (uint256 index) {
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong(bytes(message).length);

        uint256 burnedBefore = token.balanceOf(BURN_ADDRESS);
        token.safeTransferFrom(msg.sender, BURN_ADDRESS, SIGNING_COST);
        // Exact receipt is required; comparing a delta permits unrelated prior donations.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        if (token.balanceOf(BURN_ADDRESS) != burnedBefore + SIGNING_COST) revert IncorrectBurnAmount();

        // Only paid entries become visible; the guard prevents callbacks from appending in between.
        index = entries.length;
        entries.push(Entry({signer: msg.sender, message: message, timestamp: block.timestamp}));
        emit EntrySigned(index, msg.sender, message, block.timestamp);
    }

    function entryCount() external view returns (uint256) {
        return entries.length;
    }
}
