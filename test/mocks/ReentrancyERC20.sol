// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IVaultRoot} from "../../src/interfaces/IVaultRoot.sol";

contract ReentrancyERC20 is ERC20 {
    IVaultRoot root;
    address attacker;

    constructor(address _root, address _attacker) {
        root = IVaultRoot(_root);
        attacker = _attacker;
        _mint(_attacker, 1_000_000 * 1e18);
    }

    function name() public pure override returns (string memory) {
        return "ReentrancyERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "RE_ERC20";
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Malicious re-entrancy attempt
        if (msg.sender == address(root)) {
            // This will be called by root.deposit().
            // Before the state change in the first deposit() call is complete,
            // we try to re-enter. The ReentrancyGuard should prevent this.
            root.deposit(address(this), 1); 
        }

        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
} 