// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVaultRoot} from "../../src/interfaces/IVaultRoot.sol";

contract ReentrancyAttacker {
    IVaultRoot public root;

    constructor(address _root) {
        root = IVaultRoot(_root);
    }

    // Function to deposit ETH into the vault
    function deposit() external payable {
        // Forward ETH to the root contract's receive() function
        (bool success, ) = address(root).call{value: msg.value}("");
        require(success, "Deposit failed");
    }

    // Function to start the withdrawal
    function attack() external {
        root.withdraw(address(0));
    }

    // Malicious receive function to re-enter the withdraw function
    receive() external payable {
        // Unconditionally try to re-enter the withdraw function.
        // The ReentrancyGuard in VaultRoot should prevent this second call.
        root.withdraw(address(0));
    }
} 