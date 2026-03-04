// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IFoundation} from "../../src/interfaces/IFoundation.sol";

contract ReentrancyAttacker is Test {
    IFoundation public root;
    address owner;

    constructor(address _root) {
        root = IFoundation(_root);
        owner = msg.sender;
    }

    function deposit() public payable {
        (bool success, ) = address(root).call{value: msg.value}("");
        require(success, "Deposit failed");
    }

    function attack() public payable {
        root.requestRescission(address(0));
    }

    receive() external payable {
        if (address(root).balance >= 0) {
            root.requestRescission(address(0));
        }
    }
} 