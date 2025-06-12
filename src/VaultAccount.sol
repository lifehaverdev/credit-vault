// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IVaultRoot} from "./interfaces/IVaultRoot.sol";

contract VaultAccount is Ownable, ReentrancyGuard {

    // --- Events ---
    event VaultAccountCreated(address indexed accountAddress, address indexed owner, bytes32 salt);
    event DepositRecorded(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount);
    event CreditConfirmed(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event WithdrawalProcessed(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event WithdrawalRequested(address indexed vaultAccount, address indexed user, address indexed token);
    event UserWithdrawal(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount);
    event BackendStatusChanged(address indexed backend, bool isAuthorized);
    event Liquidation(address indexed vaultAccount, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);

    // --- State ---
    IVaultRoot public immutable vaultRoot;
    mapping(bytes32 => bytes32) public custody;
    
    // --- Constructor ---
    constructor(address _vaultRoot, address _owner) payable {
        vaultRoot = IVaultRoot(_vaultRoot);
        _initializeOwner(_owner);
    }

    modifier onlyVaultRoot() {
        require(msg.sender == address(vaultRoot), "Not vault root");
        _;
    }

    modifier onlyBackend() {
        require(vaultRoot.isBackend(msg.sender), "Not backend");
        require(vaultRoot.backendAllowed(), "Operator Freeze");
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

    receive() external payable {
        bytes32 key = _getCustodyKey(msg.sender, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + uint128(msg.value), escrow);
        emit DepositRecorded(address(this), msg.sender, address(0), msg.value);
        vaultRoot.recordDeposit(msg.sender, address(0), msg.value);
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        bytes32 key = _getCustodyKey(msg.sender, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit DepositRecorded(address(this), msg.sender, token, amount);
        vaultRoot.recordDeposit(msg.sender, token, amount);
    }

    function depositFor(address user, address token, uint256 amount) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        // The backend (msg.sender) must have an allowance to move the token
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit DepositRecorded(address(this), user, token, amount);
        vaultRoot.recordDeposit(user, token, amount);
    }

    function confirmCredit(address vaultAccount, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 userKey = _getCustodyKey(user, token);
        bytes32 accountKey = _getCustodyKey(address(this), token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[userKey]);
        require(userOwned >= escrowAmount, "Insufficient userOwned balance");
        custody[userKey] =  _packAmount(userOwned - uint128(escrowAmount), escrow + uint128(escrowAmount));
        if(fee > 0){
            require(escrowAmount + fee <= userOwned, "Bad Fee Math");
            (,uint128 accountEscrow) = _splitAmount(custody[accountKey]);
            custody[accountKey] =  _packAmount(0, accountEscrow + fee);
        }
        emit CreditConfirmed(vaultAccount, user, token, escrowAmount, fee, metadata);
        vaultRoot.confirmCredit(vaultAccount, user, token, escrowAmount, fee, metadata);
    }

    // --- Withdrawals ---
    function withdraw(address token) external nonReentrant {
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
            emit UserWithdrawal(address(this),msg.sender, token, userOwned);
            vaultRoot.recordWithdrawal(msg.sender, token, userOwned, 0, "");
        }else{
            emit WithdrawalRequested(address(this),msg.sender,token);
            vaultRoot.recordWithdrawalRequest(msg.sender, token, 0);
        }
    }

    function withdrawTo(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
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
        emit WithdrawalProcessed(address(this), user, token, amount, fee, metadata);
        vaultRoot.recordWithdrawal(user, token, amount, fee, metadata);
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
} 