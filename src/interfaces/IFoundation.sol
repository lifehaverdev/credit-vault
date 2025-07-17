// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFoundation {
    error NotOwner();
    error NotBackend();
    error NotCharteredFund();
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
    function requestRescission(address token) external;

    function recordContribution(address user, address token, uint256 amount) external;
    function recordDonation(address funder, address token, uint256 amount, bool isNFT, bytes32 metadata) external;
    function recordRescissionRequest(address user, address token) external;
    function recordRemittance(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external;
    function recordCommitment(address fundAddress, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external;
} 