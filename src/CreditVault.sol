// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract CreditVault is OwnableRoles, UUPSUpgradeable, Initializable, ReentrancyGuard {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Sentinel address representing ETH in balance mappings.
    address public constant ETH = address(0);

    /// @dev Maximum referral cut admin can assign (50%).
    uint16 public constant MAX_REFERRAL_BPS = 5000;

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @dev keccak256(name) => address that registered the name
    mapping(bytes32 => address) public referralOwner;

    /// @dev keccak256(name) => address that receives referral payouts
    mapping(bytes32 => address) public referralAddress;

    /// @dev keccak256(name) => basis points for this referrer (0 = use default)
    mapping(bytes32 => uint16) public referralBps;

    /// @dev Default referral cut in basis points. Initialized to 500 (5%).
    uint16 public defaultReferralBps;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Payment(
        address indexed payer,
        bytes32 indexed referralKey,
        address token,
        uint256 amount,
        uint256 protocolAmount,
        uint256 referralAmount
    );

    event NFTReceived(address indexed from, address indexed token, uint256 tokenId);
    event ERC1155TokenReceived(address indexed from, address indexed token, uint256 id, uint256 amount);

    event ReferralRegistered(bytes32 indexed key, string name, address owner);
    event ReferralAddressUpdated(bytes32 indexed key, address newAddress);
    event ReferralTransferred(bytes32 indexed key, address newOwner);
    event ReferralBpsSet(bytes32 indexed key, uint16 bps);
    event DefaultBpsSet(uint16 bps);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error AlreadyRegistered();
    error NotReferralOwner();
    error BpsExceedsCap();
    error ZeroAmount();
    error TransferFailed();
    error ZeroAddress();

    // -------------------------------------------------------------------------
    // Initializer
    // -------------------------------------------------------------------------

    function initialize(address _owner) external initializer {
        _initializeOwner(_owner);
        defaultReferralBps = 500;
    }

    // -------------------------------------------------------------------------
    // Payments
    // -------------------------------------------------------------------------

    receive() external payable nonReentrant {
        _processPayment(msg.sender, ETH, msg.value, bytes32(0));
    }

    function payETH(bytes32 referralKey) external payable nonReentrant {
        _processPayment(msg.sender, ETH, msg.value, referralKey);
    }

    function pay(address token, uint256 amount, bytes32 referralKey)
        external nonReentrant
    {
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        _processPayment(msg.sender, token, amount, referralKey);
    }

    // -------------------------------------------------------------------------
    // Referral Registry
    // -------------------------------------------------------------------------

    function register(string calldata name) external {
        bytes32 key = keccak256(bytes(name));
        if (referralOwner[key] != address(0)) revert AlreadyRegistered();
        referralOwner[key] = msg.sender;
        referralAddress[key] = msg.sender;
        emit ReferralRegistered(key, name, msg.sender);
    }

    function setAddress(bytes32 key, address to) external {
        if (referralOwner[key] != msg.sender) revert NotReferralOwner();
        if (to == address(0)) revert ZeroAddress();
        referralAddress[key] = to;
        emit ReferralAddressUpdated(key, to);
    }

    function transferName(bytes32 key, address newOwner) external {
        if (referralOwner[key] != msg.sender) revert NotReferralOwner();
        referralOwner[key] = newOwner;
        emit ReferralTransferred(key, newOwner);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    function setReferralBps(bytes32 key, uint16 bps) external onlyOwner {
        if (bps > MAX_REFERRAL_BPS) revert BpsExceedsCap();
        referralBps[key] = bps;
        emit ReferralBpsSet(key, bps);
    }

    function setDefaultBps(uint16 bps) external onlyOwner {
        if (bps > MAX_REFERRAL_BPS) revert BpsExceedsCap();
        defaultReferralBps = bps;
        emit DefaultBpsSet(bps);
    }

    function withdrawProtocol(address token, address to, uint256 amount) external onlyOwner {
        if (token == ETH) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(token, to, amount);
        }
    }

    function withdrawNFT(address token, uint256 tokenId, address to) external onlyOwner {
        SafeTransferLib.safeTransferFrom(token, address(this), to, tokenId);
    }

    function withdrawERC1155(address token, uint256 tokenId, uint256 amount, address to)
        external onlyOwner
    {
        // ERC1155 safeTransferFrom(from, to, id, amount, data)
        (bool ok,) = token.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)",
                address(this), to, tokenId, amount, ""
            )
        );
        if (!ok) revert TransferFailed();
    }

    // -------------------------------------------------------------------------
    // NFT Receivers
    // -------------------------------------------------------------------------

    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external returns (bytes4)
    {
        emit NFTReceived(from, msg.sender, tokenId);
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address from, uint256 id, uint256 amount, bytes calldata)
        external returns (bytes4)
    {
        emit ERC1155TokenReceived(from, msg.sender, id, amount);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address from, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata)
        external returns (bytes4)
    {
        for (uint256 i; i < ids.length; i++) {
            emit ERC1155TokenReceived(from, msg.sender, ids[i], amounts[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    // -------------------------------------------------------------------------
    // Multicall
    // -------------------------------------------------------------------------

    function multicall(bytes[] calldata data) external nonReentrant returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; i++) {
            (bool ok, bytes memory result) = address(this).delegatecall(data[i]);
            if (!ok) {
                assembly { revert(add(result, 0x20), mload(result)) }
            }
            results[i] = result;
        }
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _processPayment(address payer, address token, uint256 amount, bytes32 referralKey) internal {
        if (amount == 0) revert ZeroAmount();

        uint256 referralAmount;

        if (referralKey != bytes32(0) && referralAddress[referralKey] != address(0)) {
            uint16 bps = referralBps[referralKey] > 0
                ? referralBps[referralKey]
                : defaultReferralBps;
            referralAmount = amount * bps / 10000;

            if (referralAmount > 0) {
                address recipient = referralAddress[referralKey];
                if (token == ETH) {
                    SafeTransferLib.safeTransferETH(recipient, referralAmount);
                } else {
                    SafeTransferLib.safeTransfer(token, recipient, referralAmount);
                }
            }
        }

        uint256 protocolAmount = amount - referralAmount;

        emit Payment(payer, referralKey, token, amount, protocolAmount, referralAmount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
