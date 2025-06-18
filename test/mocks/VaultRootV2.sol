// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VaultRoot} from "../../src/VaultRoot.sol";

contract VaultRootV2 is VaultRoot {
    uint256 public extraVariable; // to check storage layout
    
    function version() external pure returns (string memory) {
        return "V2";
    }

    function setExtra(uint256 val) public {
        extraVariable = val;
    }
} 