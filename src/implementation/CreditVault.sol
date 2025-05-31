// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract AiCreditVault is UUPSUpgradeable, Ownable {
    // ========== Storage ==========
    mapping(address => mapping(address => uint256)) public collateralOf; // user => token => amount
    mapping(address => mapping(address => uint256)) public debtOf;       // user => token => amount
    mapping(address => bool) public isBackend;                           // authorized off-chain actors
    mapping(address => bool) public acceptedToken;                       // whitelist of accepted ERC20s

    // ========== Events ==========
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event DebtConfirmed(address indexed user, address indexed token, uint256 amount);

    // ========== Initializer ==========
    function initialize(address[] calldata tokens, address backend) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(msg.sender);
        for (uint256 i = 0; i < tokens.length; ++i) {
            acceptedToken[tokens[i]] = true;
        }
        isBackend[backend] = true;
    }

    // ========== UUPS Authorization ==========
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ========== ETH Deposit ==========
    receive() external payable {
        collateralOf[msg.sender][address(0)] += msg.value;
        emit Deposit(msg.sender, address(0), msg.value);
    }

    // ========== ERC20 Deposit ==========
    function depositERC20(address token, uint256 amount) external {
        require(acceptedToken[token], "Token not accepted");
        (bool success, ) = token.call(abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            msg.sender, address(this), amount
        ));
        require(success, "Transfer failed");
        collateralOf[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    // ========== Withdraw ==========
    function withdraw(address token, uint256 amount) external {
        uint256 bal = collateralOf[msg.sender][token];
        uint256 debt = debtOf[msg.sender][token];
        require(bal >= amount, "Insufficient collateral");
        require(bal - amount >= debt, "Debt too high");

        collateralOf[msg.sender][token] -= amount;

        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            (bool success, ) = token.call(abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender, amount
            ));
            require(success, "ERC20 transfer failed");
        }

        emit Withdraw(msg.sender, token, amount);
    }

    // ========== Off-chain Integration ==========
    function confirmDebt(address user, address token, uint256 amount) external {
        require(isBackend[msg.sender], "Not authorized");
        debtOf[user][token] = amount;
        emit DebtConfirmed(user, token, amount);
    }

    // ========== Admin Functions ==========
    function addBackend(address backend) external onlyOwner {
        isBackend[backend] = true;
    }

    function removeBackend(address backend) external onlyOwner {
        isBackend[backend] = false;
    }

    function addAcceptedToken(address token) external onlyOwner {
        acceptedToken[token] = true;
    }

    function removeAcceptedToken(address token) external onlyOwner {
        acceptedToken[token] = false;
    }
}
