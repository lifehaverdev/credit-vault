// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVaultRoot {
    error NotOwner();
    error NotBackend();
    error NotVaultAccount();
    error NotEnoughInProtocolEscrow();
    error InsufficientUserOwnedBalance();
    error InsufficientEscrowBalance();
    error BadFeeMath();
    error OperatorFrozen();
    error Create2Failed();
    error MulticallFailed();
    error MulticallOnlyByOrigin();

    function isBackend(address _backend) external view returns (bool);
    function refund() external view returns (bool);
    function backendAllowed() external view returns (bool);
    function deposit(address token, uint256 amount) external;
    function withdraw(address token) external;
    function recordDeposit(address user, address token, uint256 amount) external;
    function recordWithdrawalRequest(address user, address token) external;
    function recordWithdrawal(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external;
    function confirmCredit(address vaultAccount, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external;
} 