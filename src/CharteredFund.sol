// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IFoundation} from "./interfaces/IFoundation.sol";

contract CharteredFund is Ownable, ReentrancyGuard {

    // --- Events ---
    event FundChartered(address indexed accountAddress, address indexed owner, bytes32 salt);
    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RescissionRequested(address indexed fundAddress, address indexed user, address indexed token);
    event ContributionRescinded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event BackendStatusChanged(address indexed backend, bool isAuthorized);
    event Liquidation(address indexed fundAddress, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);
    event Donation(address indexed funder, address indexed token, uint256 amount, bool isNFT, bytes32 metadata);
    event CharterFeeWithdrawn(address indexed owner, address indexed token, uint256 amount);
    event ProtocolFeeSwept(address indexed token, uint256 amount);

    // --- State ---
    IFoundation public immutable foundation;
    mapping(bytes32 => bytes32) public custody;
    
    // --- Constructor ---
    constructor(address _foundation, address _owner) payable {
        foundation = IFoundation(_foundation);
        _initializeOwner(_owner);
    }

    modifier onlyFoundation() {
        require(msg.sender == address(foundation), "Not foundation");
        _;
    }

    modifier onlyBackend() {
        require(foundation.isBackend(msg.sender), "Not backend");
        require(foundation.backendAllowed(), "Operator Freeze");
        _;
    }

    // --- Packing/Unpacking Helpers ---
    function _getCustodyKey(address user, address token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token));
    }

    function _splitAmount(bytes32 amount) internal pure returns(uint128 userOwned, uint128 escrow) {
        userOwned = uint128(uint256(amount));
        escrow = uint128(uint256(amount >> 128));
    }
    function _packAmount(uint128 userOwned, uint128 escrow) internal pure returns(bytes32) {
        return bytes32(uint256(userOwned) | (uint256(escrow) << 128));
    }

    /// @notice Handles ERC721 token transfers into the chartered fund
    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        bytes32 key = _getCustodyKey(from, msg.sender);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + 1, escrow);
        emit ContributionRecorded(address(this), from, msg.sender, 1);
        foundation.recordContribution(from, msg.sender, 1);
        return 0x150b7a02; // IERC721Receiver.onERC721Received.selector
    }

    receive() external payable {
        bytes32 key = _getCustodyKey(msg.sender, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + uint128(msg.value), escrow);
        emit ContributionRecorded(address(this), msg.sender, address(0), msg.value);
        foundation.recordContribution(msg.sender, address(0), msg.value);
    }

    function contribute(address token, uint256 amount) external nonReentrant {
        bytes32 key = _getCustodyKey(msg.sender, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit ContributionRecorded(address(this), msg.sender, token, amount);
        foundation.recordContribution(msg.sender, token, amount);
    }

    function contributeFor(address user, address token, uint256 amount) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        // The backend (msg.sender) must have an allowance to move the token
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit ContributionRecorded(address(this), user, token, amount);
        foundation.recordContribution(user, token, amount);
    }

    function commit(address fundAddress, address user, address token, uint256 escrowAmount, uint128 charterFee, uint128 protocolFee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[userKey]);

        uint256 totalFee = uint256(charterFee) + uint256(protocolFee);
        require(userOwned >= escrowAmount + totalFee, "Insufficient userOwned balance");

        // Move user's funds to escrow and deduct fees
        custody[userKey] =  _packAmount(userOwned - uint128(escrowAmount) - uint128(totalFee), escrow + uint128(escrowAmount));

        // Accrue charter fee to the charter's owner (address(this))
        if (charterFee > 0) {
            bytes32 charterKey = _getCustodyKey(address(this), token);
            (uint128 charterOwned, uint128 charterEscrow) = _splitAmount(custody[charterKey]);
            custody[charterKey] =  _packAmount(charterOwned + charterFee, charterEscrow);
        }
        
        // Accrue protocol fee to the foundation
        if (protocolFee > 0) {
            bytes32 foundationKey = _getCustodyKey(address(foundation), token);
            (uint128 foundationOwned, uint128 foundationEscrow) = _splitAmount(custody[foundationKey]);
            custody[foundationKey] =  _packAmount(foundationOwned + protocolFee, foundationEscrow);
        }

        emit CommitmentConfirmed(fundAddress, user, token, escrowAmount, charterFee, metadata); // Note: Event may need updating for 2 fees
        foundation.recordCommitment(fundAddress, user, token, escrowAmount, charterFee, metadata); // Note: Interface may need updating
    }

    // --- Withdrawals ---
    function requestRescission(address token) external nonReentrant {
        // Here msg.sender is the user
        bytes32 key = _getCustodyKey(msg.sender, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        if(userOwned > 0){
            //In the case that operators are frozen, and credit cannot be confirmed, 
            //Allow a user to withdraw their userOwned balance
            if (token == address(0)) {
                SafeTransferLib.safeTransferETH(msg.sender, userOwned);
            } else {
                SafeTransferLib.safeTransfer(token, msg.sender, userOwned);
            }
            custody[key] =  _packAmount(0, escrow);
            emit ContributionRescinded(address(this),msg.sender, token, userOwned);
            foundation.recordRemittance(msg.sender, token, userOwned, 0, "");
        }else{
            if(foundation.refund()){
                if (token == address(0)) {
                    SafeTransferLib.safeTransferETH(msg.sender, escrow);
                } else {
                    SafeTransferLib.safeTransfer(token, msg.sender, escrow);
                }
            } else {
                emit RescissionRequested(address(this),msg.sender,token);
                foundation.recordRescissionRequest(msg.sender, token);
            }
            
        }
    }

    function remit(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (, uint128 escrow) = _splitAmount(custody[key]);
        require(escrow >= amount + fee, "Insufficient escrow balance");
        escrow -= uint128(amount);
        if (fee > 0) {
            bytes32 accountKey = _getCustodyKey(address(this), token);
            (, uint128 protocolEscrow) = _splitAmount(custody[accountKey]);
            custody[accountKey] =  _packAmount(0, protocolEscrow + fee);
            if(amount == 0){
                emit Liquidation(address(this), user, token, fee, metadata);
            }
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

    function allocate(address user, address token, uint256 amount) external onlyBackend {
        bytes32 protocolKey = _getCustodyKey(address(this), token);
        (, uint128 protocolEscrow) = _splitAmount(custody[protocolKey]);

        require(protocolEscrow >= amount, "Not enough in protocol escrow");

        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 userEscrow) = _splitAmount(custody[userKey]);

        // Subtract from protocol escrow
        protocolEscrow -= uint128(amount);
        custody[protocolKey] = _packAmount(0, protocolEscrow);

        // Add to user escrow
        custody[userKey] = _packAmount(userOwned, userEscrow + uint128(amount));

        emit CommitmentConfirmed(address(this), user, token, amount, 0, "ALLOCATED");
    }

    function withdrawCharterFees(address token, uint256 amount) external nonReentrant onlyOwner {
        bytes32 charterKey = _getCustodyKey(address(this), token);
        (uint128 charterOwned, uint128 charterEscrow) = _splitAmount(custody[charterKey]);
        
        require(charterOwned >= amount, "Insufficient charter balance");

        custody[charterKey] = _packAmount(charterOwned - uint128(amount), charterEscrow);

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(owner(), amount);
        } else {
            SafeTransferLib.safeTransfer(token, owner(), amount);
        }

        emit CharterFeeWithdrawn(owner(), token, amount);
    }

    function sweepProtocolFees(address token) external onlyBackend nonReentrant {
        bytes32 foundationKey = _getCustodyKey(address(foundation), token);
        (uint128 foundationOwned, uint128 foundationEscrow) = _splitAmount(custody[foundationKey]);
        
        require(foundationOwned > 0, "No protocol fees to sweep");

        custody[foundationKey] = _packAmount(0, foundationEscrow);

        if (token == address(0)) {
            // IFoundation(foundation).recordProtocolFee{value: foundationOwned}(token, foundationOwned);
        } else {
            // SafeTransferLib.safeTransfer(token, address(foundation), foundationOwned);
            // IFoundation(foundation).recordProtocolFee(token, foundationOwned);
        }

        emit ProtocolFeeSwept(token, foundationOwned);
    }

    // --- Admin & Utility ---
    function multicall(bytes[] calldata data) external onlyBackend {
        require(msg.sender == tx.origin, "Multicall can only be called by the origin");
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, ) = address(this).delegatecall(data[i]);
            require(success, "Multicall failed");
        }
    }
    
    function performCalldata(address target, bytes calldata data) external payable onlyOwner {
        (bool success, ) = target.call{value: msg.value}(data);
        require(success, "Execution failed");
    }

    function donate(address token, uint256 amount, bytes32 metadata, bool isNFT) external payable nonReentrant {
        if (token == address(0)) {
            require(msg.value == amount, "ETH value mismatch");
            bytes32 key = _getCustodyKey(address(this), address(0));
            (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        } else if (isNFT) {
            // ERC721 transferFrom(tx.origin, address(this), amount) where amount is tokenId
            (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, tx.origin, address(this), amount));
            require(success && (data.length == 0 || abi.decode(data, (bool))), "NFT transfer failed");
            bytes32 key = _getCustodyKey(address(this), token);
            (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(userOwned + 1, escrow);
        } else {
            // ERC20
            SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
            bytes32 key = _getCustodyKey(address(this), token);
            (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        }
        emit Donation(msg.sender, token, amount, isNFT, metadata);
        try foundation.recordDonation(msg.sender, token, amount, isNFT, metadata) {
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory lowLevelData) {
            assembly { revert(add(lowLevelData, 32), mload(lowLevelData)) }
        }
    }
} 