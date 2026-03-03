// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreditVault} from "src/CreditVault.sol";

/// @dev Attempts to re-enter payETH during ETH referral push
contract ReentrancyAttackerV2 {
    CreditVault public vault;
    bytes32 public attackerKey;
    bool public attacked;

    constructor(address _vault, bytes32 _key) {
        vault = CreditVault(payable(_vault));
        attackerKey = _key;
    }

    // This receives the referral push during pay — attempts reentry
    receive() external payable {
        if (!attacked) {
            attacked = true;
            vault.payETH{value: msg.value}(bytes32(0));
        }
    }
}
