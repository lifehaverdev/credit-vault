// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";

contract EncodeInitializeScript is Script {
    function run() public pure {
        bytes memory encoded = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            0x01152530028bd834EDbA9744885A882D025D84F6,  // foundation
            0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6   // owner
        );
        
        console2.logBytes(encoded);
        console2.logBytes32(keccak256(encoded));
    }
}
