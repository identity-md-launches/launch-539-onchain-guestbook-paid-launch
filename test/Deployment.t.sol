// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract DeploymentProbe {
    function deploy(bytes memory creationCode, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(deployed != address(0), "constructor failed");
    }
}

contract DeploymentTest is Test {
    function test_factoryStyleDeploymentPreservesSupplyAndConfiguresBook() public {
        DeploymentProbe factory = new DeploymentProbe();
        LaunchToken token = LaunchToken(factory.deploy(type(LaunchToken).creationCode, bytes32(uint256(1))));
        Guestbook book = Guestbook(
            factory.deploy(
                abi.encodePacked(type(Guestbook).creationCode, abi.encode(address(token))), bytes32(uint256(2))
            )
        );

        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(factory)), token.totalSupply());
        assertEq(address(book.token()), address(token));
        assertEq(book.entryCount(), 0);
        assertEq(token.balanceOf(address(book)), 0);
        _assertRuntime(address(token));
        _assertRuntime(address(book));
    }

    function _assertRuntime(address target) private view {
        bytes memory code = target.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 opcode = uint8(code[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }
}
