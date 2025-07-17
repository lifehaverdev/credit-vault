/*                    ____////////////////////////////////////
                 ____ \__ \///////////////////////////////////
                 \__ \__/ / __////////////////////////////////
                 __/ ____ \ \ \    ____///////////////////////
                / __ \__ \ \/ / __ \__ \//////////////////////
           ____ \ \ \__/ / __ \/ / __/ / __///////////////////
      ____ \__ \ \/ ____ \/ / __/ / __ \ \ \//////////////////
      \__ \__/ / __ \__ \__/ / __ \ \ \ \/////////////////////
      __/ ____ \ \ \__/ ____ \ \ \ \/ / __////////////////////
     / __ \__ \ \/ ____ \__ \ \/ / __ \/ /////////////////////
     \ \ \__/ / __ \__ \__/ / __ \ \ \__//////////////////////
      \/ ____ \/ / __/ ____ \ \ \ \/ ____/////////////////////
         \__ \__/ / __ \__ \ \/ / __ \__ \////////////////////
         __/ ____ \ \ \__/ / __ \/ / __/ / __/////////////////
        / __ \__ \ \/ ____ \/ / __/ / __ \/ //////////////////
        \/ / __/ / __ \__ \__/ / __ \/ / __///////////////////
        __/ / __ \ \ \__/ ____ \ \ \__/ / __//////////////////
       / __ \ \ \ \/ ____ \__ \ \/ ____ \/ ///////////////////
       \ \ \ \/ / __ \__ \__/ / __ \__ \__////////////////////
        \/ / __ \/ / __/ ____ \ \ \__/////////////////////////
           \ \ \__/ / __ \__ \ \//////////////////////////////
            \/      \ \ \__/ / __/////////////////////////////
                     \/ ____ \/ //////////////////////////////
                        \__ \__///////////////////////////////
                        __//////////////////////////////////*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {CharteredFund} from "./CharteredFund.sol";

interface ICreate2Factory {
    function deploy(bytes calldata _initCode, bytes32 _salt) external returns (address);
}

contract Foundation is UUPSUpgradeable, Initializable, ReentrancyGuard {

    /*
         /\\       \\
        /  \\       \\
       /    \\       \\
      /      \\_______\\ 
      \\      /       /
    ___\\    /   ____/___
   /\\   \\  /   /\\       \\
  /  \\   \\/___/  \\       \\  /// STATE VARIABLES ///
 /    \\       \\   \\       \\
/      \\_______\\   \\_______\\
\\      /       /   /       /
 \\    /       /   /       /
  \\  /       /\\  /       /
   \\/_______/  \\/_______/ 
    */

    mapping(bytes32 => bytes32) public custody; // keccak256(user,token) => keccak256(userOwned, escrow)
    mapping(address => bool) public isCharteredFund;
    mapping(address => bool) public isBackend;
    bool internal _backendAllowed = true;
    bool public refund = false;
    address public ownerNFT;
    uint256 public ownerTokenId;

    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// EVENTS & ERRORS ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */
    event FundChartered(address indexed fundAddress, address indexed owner, bytes32 salt);
    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RescissionRequested(address indexed fundAddress, address indexed user, address indexed token);
    event ContributionRescinded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event BackendStatusChanged(address indexed backend, bool isAuthorized);
    event Liquidation(address indexed fundAddress, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);
    event RefundChanged(bool isRefund);
    event Donation(address indexed funder, address indexed token, uint256 amount, bool isNFT, bytes32 metadata);

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
    error InvalidFundAddressPrefix();
    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// MODIFIERS ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */

    /// @notice Restricts function access to the current owner of token MiladyStation NFT ID 598.
    /// @dev This enforces ownership via an ERC721 `ownerOf(uint256)` call, rather than OpenZeppelin's Ownable pattern.
    ///      The NFT address is hardcoded as 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0.
    ///      If the token is transferred, contract control transfers with it. 
    modifier onlyOwner() {
        (, bytes memory data) = ownerNFT.call(abi.encodeWithSelector(0x6352211e, ownerTokenId));
        if(abi.decode(data, (address)) != msg.sender) revert NotOwner();
        _;
    }

    modifier onlyBackend() {
        if(!isBackend[msg.sender]) revert NotBackend();
        if(!_backendAllowed) revert OperatorFrozen();
        _;
    }

    modifier onlyCharteredFund() {
        if(!isCharteredFund[msg.sender]) revert NotCharteredFund();
        _;
    }
    
    /*
      ____
     /\\___\\  /// HELPER FUNCTIONS ///
    /\\ \\___\\
    \\ \\/ / /
     \\/_/_/ 

    */
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

    function backendAllowed() external view returns (bool) {
        return _backendAllowed;
    }

    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// OWNER & OPERATOR MANAGEMENT ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */

    function setBackend(address _backend, bool _isAuthorized) external onlyOwner {
        isBackend[_backend] = _isAuthorized;
        emit BackendStatusChanged(_backend, _isAuthorized);
    }

    function setFreeze(bool isFrozen) external onlyOwner {
        _backendAllowed = isFrozen;
        emit OperatorFreeze(isFrozen);
    }

    function setRefund(bool _refund) external onlyOwner {
        refund = _refund;
        emit RefundChanged(_refund);
    }

    /**
    * @notice Computes the expected address for a new chartered fund without deploying it.
    * @param _owner The address that will own the new fund.
    * @param _salt The 32-byte salt for the CREATE2 operation.
    * @return The computed address of the new chartered fund.
    */
    function computeCharterAddress(address _owner, bytes32 _salt) external view returns (address) {
        bytes memory bytecode = type(CharteredFund).creationCode;
        bytes memory constructorArgs = abi.encode(address(this), _owner);
        bytes32 initCodeHash = keccak256(abi.encodePacked(bytecode, constructorArgs));
        
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            _salt,
            initCodeHash
        )))));
    }

    function charterFund(address _owner, bytes32 _salt) external onlyBackend returns (address) {
        bytes memory bytecode = type(CharteredFund).creationCode;
        bytes memory constructorArgs = abi.encode(address(this), _owner);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        address fund;
        assembly {
            fund := create2(0, add(initCode, 0x20), mload(initCode), _salt)
        }
        if(fund == address(0)) revert Create2Failed();

        isCharteredFund[fund] = true;
        emit FundChartered(fund, _owner, _salt);
        return fund;
    }

    function multicall(bytes[] calldata data) external onlyBackend {
        if(msg.sender != tx.origin) revert MulticallOnlyByOrigin();
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, ) = address(this).delegatecall(data[i]);
            if(!success) revert MulticallFailed();
        }
    }
    
    function performCalldata(address target, bytes calldata data) external payable onlyOwner {
        (bool success, ) = target.call{value: msg.value}(data);
        if(!success) revert MulticallFailed();
    }

    function allocate(address user, address token, uint256 amount) external onlyBackend {
        bytes32 protocolKey = _getCustodyKey(address(this), token);
        (, uint128 protocolEscrow) = _splitAmount(custody[protocolKey]);

        if(protocolEscrow < amount) revert NotEnoughInProtocolEscrow();
        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 userEscrow) = _splitAmount(custody[userKey]);

        // Subtract from protocol escrow
        protocolEscrow -= uint128(amount);
        custody[protocolKey] = _packAmount(0, protocolEscrow);

        // Add to user escrow
        custody[userKey] = _packAmount(userOwned, userEscrow + uint128(amount));

        emit CommitmentConfirmed(address(this), user, token, amount, 0, "ALLOCATED");
    }

    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// CONTRIBUTIONS ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */

    receive() external payable {
        bytes32 key = _getCustodyKey(msg.sender, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + uint128(msg.value), escrow);
        emit ContributionRecorded(address(this), msg.sender, address(0), msg.value);
    }

    /// @notice Handles ERC721 token transfers into the vault
    /// @dev Returns the selector required to accept ERC721s
    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        // Treat `msg.sender` as the NFT contract address
        bytes32 key = _getCustodyKey(from, msg.sender);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);

        // We increment the user's count of NFTs from this contract
        custody[key] = _packAmount(userOwned + 1, escrow);

        emit ContributionRecorded(address(this), from, msg.sender, 1); // tokenId is not stored here, just count
        return 0x150b7a02; // IERC721Receiver.onERC721Received.selector
    }

    function contribute(address token, uint256 amount) external nonReentrant {
        bytes32 key = _getCustodyKey(msg.sender, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit ContributionRecorded(address(this), msg.sender, token, amount);
    }

    function contributeFor(address user, address token, uint256 amount) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        // The backend (msg.sender) must have an allowance to move the token
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit ContributionRecorded(address(this), user, token, amount);
    }

    function recordContribution(address user, address token, uint256 amount) external payable onlyCharteredFund nonReentrant {
        emit ContributionRecorded(msg.sender, user, token, amount);
    }

    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// REMITTANCES & RESCISSIONS ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */

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
        }else{
            if(refund){
                if (token == address(0)) {
                    SafeTransferLib.safeTransferETH(msg.sender, escrow);
                } else {
                    SafeTransferLib.safeTransfer(token, msg.sender, escrow);
                }
                custody[key] = _packAmount(userOwned, 0); // zero out escrow
                emit ContributionRescinded(address(this), msg.sender, token, escrow);
            } else {
                emit RescissionRequested(address(this),msg.sender,token);
            }
        }
    }

    function remit(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        if(escrow < amount + fee) revert InsufficientEscrowBalance();
        
        escrow -= (uint128(amount) + fee);
        custody[key] = _packAmount(userOwned, escrow);

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
    }

    function recordRescissionRequest(address user, address token) external onlyCharteredFund nonReentrant {
        emit RescissionRequested(msg.sender, user, token);
    }

    function recordRemittance(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyCharteredFund nonReentrant {
        emit RemittanceProcessed(msg.sender, user, token, amount, fee, metadata);
    }

    function recordCommitment(address fundAddress, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external onlyCharteredFund nonReentrant {
        emit CommitmentConfirmed(fundAddress, user, token, escrowAmount, fee, metadata);
    }

    function commit(address fundAddress, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 userKey = _getCustodyKey(user, token);
        bytes32 accountKey = _getCustodyKey(address(this), token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[userKey]);
        if(userOwned < escrowAmount) revert InsufficientUserOwnedBalance();
        custody[userKey] =  _packAmount(userOwned - uint128(escrowAmount), escrow + uint128(escrowAmount));
        if(fee > 0){
            if(escrowAmount + fee > userOwned) revert BadFeeMath();
            (,uint128 accountEscrow) = _splitAmount(custody[accountKey]);
            custody[accountKey] =  _packAmount(0, accountEscrow + fee);
        }
        emit CommitmentConfirmed(fundAddress, user, token, escrowAmount, fee, metadata);
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
    }

    function recordDonation(address funder, address token, uint256 amount, bool isNFT, bytes32 metadata) external onlyCharteredFund nonReentrant {
        emit Donation(funder, token, amount, isNFT, metadata);
    }

    /*

    ________
   /_______/\\
   \\ \\    / /
 ___\\ \\__/_/___     /// UPGRADEABILITY ///
/____\\ \\______/\\
\\ \\   \\/ /   / /
 \\ \\  / /\\  / /
  \\ \\/ /\\ \\/ /
   \\_\\/  \\_\\/

   
    */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// Initialization ///
    function initialize(address _ownerNFT, uint256 _ownerTokenId) external initializer {
        ownerNFT = _ownerNFT;
        ownerTokenId = _ownerTokenId;
    }
} 