// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IFoundation} from "../../src/interfaces/IFoundation.sol";

contract ReentrancyERC20 is ERC20 {
    IFoundation public root;
    address public attacker;

    constructor(address _root, address _attacker) {
        root = IFoundation(_root);
        attacker = _attacker;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function name() public pure override returns (string memory) {
        return "ReentrancyERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "RE_ERC20";
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Maliciously re-enter the root contract during a transfer
        if (to == address(root)) {
            // Attempt to call a function that is protected by nonReentrant
            root.requestRescission(address(0));
        }
        
        // Comply with the ERC20 standard
        uint256 fromAllowance = allowance(from, msg.sender);
        if (fromAllowance != type(uint256).max) {
            _spendAllowance(from, msg.sender, amount);
        }

        _transfer(from, to, amount);
        return true;
    }
} 