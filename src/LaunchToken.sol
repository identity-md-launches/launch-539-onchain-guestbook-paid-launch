// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply, 18-decimal payment token for the guestbook launch.
contract LaunchToken is ERC20 {
    /// @dev The launch factory receives the entire supply and handles its distribution.
    constructor() ERC20("Guestbook Token", "GUEST") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
