// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IFoundation} from "./interfaces/IFoundation.sol";
import {Keep} from "./Keep.sol";

/// @title CharteredFundImplementation
/// @notice Upgrade-friendly version of `CharteredFund` meant to be used behind a beacon / proxy.
///         The runtime behaviour is identical to `CharteredFund` except construction logic has been
///         moved to an `initialize` function, and the `foundation` reference is stored in
///         write-able storage (not `immutable`).
contract CharteredFundImplementation is Keep, Ownable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event FundChartered(address indexed accountAddress, address indexed owner, bytes32 salt);
    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RescissionRequested(address indexed fundAddress, address indexed user, address indexed token);
    event ContributionRescinded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event MarshalStatusChanged(address indexed marshal, bool isAuthorized);
    event Liquidation(address indexed fundAddress, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);
    event Donation(address indexed funder, address indexed token, uint256 amount, bool isNFT, bytes32 metadata);
    event CharterFeeWithdrawn(address indexed owner, address indexed token, uint256 amount);
    event ProtocolFeeSwept(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                    STATE
    //////////////////////////////////////////////////////////////////////////*/

    bool private _initialized;
    IFoundation public foundation; // storage (not immutable)

    /*//////////////////////////////////////////////////////////////////////////
                                INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Initializes the implementation clone / proxy.
    /// @param _foundation  Address of the `Foundation` contract.
    /// @param _owner       Initial owner (mapped to Ownable's `owner()`).
    function initialize(address _foundation, address _owner) external {
        if (_initialized) revert("AlreadyInit");
        _initialized = true;

        foundation = IFoundation(_foundation);
        _initializeOwner(_owner);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier onlyFoundation() {
        if (msg.sender != address(foundation)) revert Auth();
        _;
    }

    modifier onlyMarshal() {
        if (!foundation.isMarshal(msg.sender) || foundation.marshalFrozen()) revert Auth();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                             ERC721 RECEIVER HOOK
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Handles ERC721 token transfers into the chartered fund
    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        _handleERC721(msg.sender, from);
        emit ContributionRecorded(address(this), from, msg.sender, 1);
        foundation.recordContribution(from, msg.sender, 1);
        return 0x150b7a02;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   RECEIVE ETH
    //////////////////////////////////////////////////////////////////////////*/

    receive() external payable {
        _receiveETH(msg.sender, msg.value);
        emit ContributionRecorded(address(this), msg.sender, address(0), msg.value);
        foundation.recordContribution(msg.sender, address(0), msg.value);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               CONTRIBUTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function contribute(address token, uint256 amount) external nonReentrant {
        _contributeFor(msg.sender, msg.sender, token, amount);
        emit ContributionRecorded(address(this), msg.sender, token, amount);
        foundation.recordContribution(msg.sender, token, amount);
    }

    /**
     * @notice Sponsor deposits `amount` of `token` into the fund on behalf of `user`.
     * @dev Open to any caller; tokens are transferred from the sponsor (msg.sender).
     */
    function contributeFor(address user, address token, uint256 amount) external nonReentrant {
        _contributeFor(msg.sender, user, token, amount);
        emit ContributionRecorded(address(this), user, token, amount);
        foundation.recordContribution(user, token, amount);
    }

    function commit(
        address fundAddress,
        address user,
        address token,
        uint256 escrowAmount,
        uint128 charterFee,
        uint128 protocolFee,
        bytes calldata metadata
    ) external onlyMarshal nonReentrant {
        (bool ok, uint128 ownedBefore) = _commitEscrow(user, token, escrowAmount);
        if (!ok) revert Math();

        uint256 totalFee = uint256(charterFee) + uint256(protocolFee);
        if (totalFee > ownedBefore - escrowAmount) revert Math();

        // Charter fee to this contract's owned balance
        if (charterFee > 0) {
            bytes32 charterKey = _getCustodyKey(address(this), token);
            (uint128 charterOwned, uint128 charterEscrow) = _splitAmount(custody[charterKey]);
            custody[charterKey] = _packAmount(charterOwned + charterFee, charterEscrow);
        }

        // Protocol fee to foundation owned balance
        if (protocolFee > 0) {
            bytes32 foundationKey = _getCustodyKey(address(foundation), token);
            (uint128 foundationOwned, uint128 foundationEscrow) = _splitAmount(custody[foundationKey]);
            custody[foundationKey] = _packAmount(foundationOwned + protocolFee, foundationEscrow);
        }

        emit CommitmentConfirmed(fundAddress, user, token, escrowAmount, charterFee, metadata);
        foundation.recordCommitment(fundAddress, user, token, escrowAmount, charterFee, metadata);
    }

    function donate(
        address token,
        uint256 amount,
        bytes32 metadata,
        bool isNFT
    ) external payable nonReentrant {
        if (token == address(0) && msg.value < amount) revert Math();
        _donate(msg.sender, token, amount, isNFT);
        emit Donation(msg.sender, token, amount, isNFT, metadata);
        try foundation.recordDonation(msg.sender, token, amount, isNFT, metadata) {
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory lowLevelData) {
            assembly {
                revert(add(lowLevelData, 32), mload(lowLevelData))
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               WITHDRAWALS
    //////////////////////////////////////////////////////////////////////////*/

    function requestRescission(address token) external nonReentrant {
        (RescissionOutcome outcome, uint128 amt) = _requestRescission(msg.sender, token, foundation.refund());
        if (outcome == RescissionOutcome.UserOwnedWithdrawn) {
            emit ContributionRescinded(address(this), msg.sender, token, amt);
            foundation.recordRemittance(msg.sender, token, amt, 0, "");
        } else if (outcome == RescissionOutcome.EscrowRefunded) {
            // Escrow refunded; treat similarly
            emit ContributionRescinded(address(this), msg.sender, token, amt);
        } else {
            emit RescissionRequested(address(this), msg.sender, token);
            foundation.recordRescissionRequest(msg.sender, token);
        }
    }

    function remit(
        address user,
        address token,
        uint256 amount,
        uint128 fee,
        bytes calldata metadata
    ) external onlyMarshal nonReentrant {
        if (!_remit(user, token, amount, fee)) revert Math();

        if (fee > 0 && amount == 0) {
            emit Liquidation(address(this), user, token, fee, metadata);
        }

        if (amount > 0) {
            if (token == address(0)) {
                SafeTransferLib.safeTransferETH(user, amount);
            } else {
                SafeTransferLib.safeTransfer(token, user, amount);
            }
        }
        emit RemittanceProcessed(address(this), user, token, amount, fee, metadata);
        foundation.recordRemittance(user, token, amount, fee, metadata);
    }

    function allocate(address user, address token, uint256 amount) external onlyMarshal {
        if (!_allocate(user, token, amount)) revert Math();
        emit CommitmentConfirmed(address(this), user, token, amount, 0, "ALLOCATED");
    }

    function withdrawCharterFees(address token, uint256 amount) external nonReentrant onlyOwner {
        bytes32 charterKey = _getCustodyKey(address(this), token);
        (uint128 charterOwned, uint128 charterEscrow) = _splitAmount(custody[charterKey]);

        if (charterOwned < amount) revert Math();

        custody[charterKey] = _packAmount(charterOwned - uint128(amount), charterEscrow);

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(owner(), amount);
        } else {
            SafeTransferLib.safeTransfer(token, owner(), amount);
        }

        emit CharterFeeWithdrawn(owner(), token, amount);
    }

    

    /*//////////////////////////////////////////////////////////////////////////
                             ADMIN & UTILITY
    //////////////////////////////////////////////////////////////////////////*/

    function sweepProtocolFees(address token) external onlyMarshal nonReentrant {
        bytes32 foundationKey = _getCustodyKey(address(foundation), token);
        (uint128 foundationOwned, uint128 foundationEscrow) = _splitAmount(custody[foundationKey]);

        if (foundationOwned == 0) revert Math();

        custody[foundationKey] = _packAmount(0, foundationEscrow);

        if (token == address(0)) {
            // IFoundation(foundation).recordProtocolFee{value: foundationOwned}(token, foundationOwned);
        } else {
            // SafeTransferLib.safeTransfer(token, address(foundation), foundationOwned);
            // IFoundation(foundation).recordProtocolFee(token, foundationOwned);
        }

        emit ProtocolFeeSwept(token, foundationOwned);
    }

    function multicall(bytes[] calldata data) external onlyMarshal {
        if (msg.sender != tx.origin) revert Auth();
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, ) = address(this).delegatecall(data[i]);
            if (!success) revert Fail();
        }
    }

    function performCalldata(address target, bytes calldata data) external payable onlyOwner {
        (bool success, ) = target.call{value: msg.value}(data);
        if (!success) revert Fail();
    }

    
}
