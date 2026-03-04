// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Foundation} from "../../src/Foundation.sol";

contract FoundationV2 is Foundation {
    function version() public pure returns (string memory) {
        return "V2";
    }

    // Example of a new function in V2
    function newV2Function() public pure returns (bool) {
        return true;
    }
} 