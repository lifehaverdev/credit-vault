// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFoundation {

    error Auth();
    error Math();
    error Fail();

    function isMarshal(address _marshal) external view returns (bool);
    function refund() external view returns (bool);
    function marshalFrozen() external view returns (bool);
    function requestRescission(address token) external;

    function recordContribution(address user, address token, uint256 amount) external;
    function recordDonation(address funder, address token, uint256 amount, bool isNFT, bytes32 metadata) external;
    function recordRescissionRequest(address user, address token) external;
    function recordRemittance(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external;
    function recordCommitment(address fundAddress, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external;
} 