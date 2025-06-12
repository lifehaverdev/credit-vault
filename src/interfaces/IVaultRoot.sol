// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVaultRoot {
    function isBackend(address _backend) external view returns (bool);
    function backendAllowed() external view returns (bool);
    function recordDeposit(address user, address token, uint256 amount) external;
    function recordWithdrawalRequest(address user, address token, uint256 amount) external;
    function recordWithdrawal(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external;
    function confirmCredit(address vaultAccount, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external;
} 