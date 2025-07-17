// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Foundation} from "src/Foundation.sol";

interface ICreate2Factory {
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
}

contract VanityTest is Test {
    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address FACTORY = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    // !! IMPORTANT: Replace with the new salt you find after running the updated mining script !!
    bytes32 salt = bytes32(uint256(21245)); 

    function testCreate2AddressMatches() public {
        bytes memory bytecode = type(Foundation).creationCode;
        bytes32 initCodeHash = keccak256(bytecode);

        // Replicate the factory's _guard function for a simple salt
        bytes32 guardedSalt = keccak256(abi.encode(salt));

        address expected = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), FACTORY, guardedSalt, initCodeHash))
                )
            )
        );

        vm.startPrank(admin);

        // You pass the original salt to the factory function
        address deployed = ICreate2Factory(FACTORY).deployCreate2(salt, bytecode);

        vm.stopPrank();

        assertEq(deployed, expected, "CREATE2 address mismatch!");
        emit log_named_address("Deployed Foundation to", deployed);
    }

}
