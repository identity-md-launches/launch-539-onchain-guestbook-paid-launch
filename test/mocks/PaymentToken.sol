// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Guestbook} from "../../src/Guestbook.sol";

/// @dev Adversarial fixture only; production deployments use LaunchToken.
contract PaymentToken is ERC20 {
    enum Mode {
        Normal,
        ReturnFalse,
        ReturnNothing,
        NoMovement,
        Fee,
        CatchReentry,
        BubbleReentry,
        RevertPayment
    }

    Mode public mode;
    bytes public callbackError;
    bool public callbackSucceeded;
    uint8 private immutable _decimals;

    error PaymentReverted();

    constructor(uint8 decimals_) ERC20("Test Payment", "TEST") {
        _decimals = decimals_;
        _mint(msg.sender, 1_000 ether);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (mode == Mode.NoMovement) return true;
        if (mode == Mode.Fee) {
            _spendAllowance(from, msg.sender, value);
            _transfer(from, to, value - 1);
            _transfer(from, address(this), 1);
            return true;
        }

        super.transferFrom(from, to, value);
        if (mode == Mode.ReturnFalse) return false;
        if (mode == Mode.ReturnNothing) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        if (mode == Mode.RevertPayment) revert PaymentReverted();
        if (mode == Mode.CatchReentry) {
            try Guestbook(msg.sender).sign("unpaid callback") returns (uint256) {
                callbackSucceeded = true;
            } catch (bytes memory reason) {
                callbackError = reason;
            }
        }
        if (mode == Mode.BubbleReentry) {
            Guestbook(msg.sender).sign("unpaid callback");
        }
        return true;
    }
}
