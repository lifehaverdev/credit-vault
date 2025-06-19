/*////////////////////////////////////////////////////////////
                      ____////////////////////////////////////
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
                        __////////////////////////////////////
////////////////////////////////////////////////////////////*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {VaultAccount} from "./VaultAccount.sol";

interface ICreate2Factory {
    function deploy(bytes calldata _initCode, bytes32 _salt) external returns (address);
}

contract VaultRoot is UUPSUpgradeable, Initializable, ReentrancyGuard {

    /*
         /\       \
        /  \       \
       /    \       \
      /      \_______\ 
      \      /       /
    ___\    /   ____/___
   /\   \  /   /\       \
  /  \   \/___/  \       \  /// STATE VARIABLES ///
 /    \       \   \       \
/      \_______\   \_______\
\      /       /   /       /
 \    /       /   /       /
  \  /       /\  /       /
   \/_______/  \/_______/ 
    */

    mapping(bytes32 => bytes32) public custody; // vaultAccount => keccak256(user,token) => balance
    mapping(address => bool) public isVaultAccount;
    mapping(address => bool) public isBackend;
    bool internal _backendAllowed = true;
    bool public refund = false;

    /*
       ______
      /\_____\     
     _\ \__/_/_   
    /\_\ \_____\  /// EVENTS ///
    \ \ \/ / / /   
     \ \/ /\/ /   
      \/_/\/_/    

    */
    event VaultAccountCreated(address indexed accountAddress, address indexed owner, bytes32 salt);
    event DepositRecorded(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount);
    event CreditConfirmed(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event WithdrawalProcessed(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event WithdrawalRequested(address indexed vaultAccount, address indexed user, address indexed token);
    event UserWithdrawal(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount);
    event BackendStatusChanged(address indexed backend, bool isAuthorized);
    event Liquidation(address indexed vaultAccount, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);
    event RefundChanged(bool isRefund);

    /*
       ______
      /\_____\     
     _\ \__/_/_   
    /\_\ \_____\  /// MODIFIERS ///
    \ \ \/ / / /   
     \ \/ /\/ /   
      \/_/\/_/    

    */

    /// @notice Restricts function access to the current owner of token MiladyStation NFT ID 598.
    /// @dev This enforces ownership via an ERC721 `ownerOf(uint256)` call, rather than OpenZeppelin's Ownable pattern.
    ///      The NFT address is hardcoded as 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0.
    ///      If the token is transferred, contract control transfers with it. 
    modifier onlyOwner() {
        (, bytes memory data) = (0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).call(abi.encodeWithSelector(0x6352211e, 598));
        require(abi.decode(data, (address)) == msg.sender, "Not the owner of the token");
        _;
    }

    modifier onlyBackend() {
        require(isBackend[msg.sender], "Not backend");
        require(_backendAllowed, "Operator Freeze");
        _;
    }

    modifier onlyVaultAccount() {
        require(isVaultAccount[msg.sender], "Not vault account");
        _;
    }
    
    /*
      ____
     /\___\  /// HELPER FUNCTIONS ///
    /\ \___\
    \ \/ / /
     \/_/_/ 

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
      /\_____\     
     _\ \__/_/_   
    /\_\ \_____\  /// OWNER & OPERATOR MANAGEMENT ///
    \ \ \/ / / /   
     \ \/ /\/ /   
      \/_/\/_/    

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

    function createVaultAccount(address _owner, bytes32 _salt) external onlyBackend returns (address) {
        bytes memory bytecode = type(VaultAccount).creationCode;
        bytes memory constructorArgs = abi.encode(address(this), _owner);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        address account;
        assembly {
            account := create2(0, add(initCode, 0x20), mload(initCode), _salt)
        }
        require(account != address(0), "CREATE2_FAILED");

        isVaultAccount[account] = true;
        emit VaultAccountCreated(account, _owner, _salt);
        return account;
    }

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

    function blessEscrow(address user, address token, uint256 amount) external onlyBackend {
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

        emit CreditConfirmed(address(this), user, token, amount, 0, "BLESSED");
    }

    /*
       ______
      /\_____\     
     _\ \__/_/_   
    /\_\ \_____\  /// DEPOSITS ///
    \ \ \/ / / /   
     \ \/ /\/ /   
      \/_/\/_/    

    */

    receive() external payable {
        bytes32 key = _getCustodyKey(msg.sender, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + uint128(msg.value), escrow);
        emit DepositRecorded(address(this), msg.sender, address(0), msg.value);
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

        emit DepositRecorded(address(this), from, msg.sender, 1); // tokenId is not stored here, just count
        return 0x150b7a02; // IERC721Receiver.onERC721Received.selector
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        bytes32 key = _getCustodyKey(msg.sender, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit DepositRecorded(address(this), msg.sender, token, amount);
    }

    function depositFor(address user, address token, uint256 amount) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        // The backend (msg.sender) must have an allowance to move the token
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
        emit DepositRecorded(address(this), user, token, amount);
    }

    function recordDeposit(address user, address token, uint256 amount) external payable onlyVaultAccount nonReentrant {
        emit DepositRecorded(msg.sender, user, token, amount);
    }

    /*
       ______
      /\_____\     
     _\ \__/_/_   
    /\_\ \_____\  /// WITHDRAWALS ///
    \ \ \/ / / /   
     \ \/ /\/ /   
      \/_/\/_/    

    */

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
        }else{
            if(refund){
                if (token == address(0)) {
                    SafeTransferLib.safeTransferETH(msg.sender, escrow);
                } else {
                    SafeTransferLib.safeTransfer(token, msg.sender, escrow);
                }
                custody[key] = _packAmount(userOwned, 0); // zero out escrow
                emit UserWithdrawal(address(this), msg.sender, token, escrow);
            } else {
                emit WithdrawalRequested(address(this),msg.sender,token);
            }
        }
    }

    function withdrawTo(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyBackend nonReentrant {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        require(escrow >= amount + fee, "Insufficient escrow balance");
        
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
        emit WithdrawalProcessed(address(this), user, token, amount, fee, metadata);
    }

    function recordWithdrawalRequest(address user, address token) external onlyVaultAccount nonReentrant {
        emit WithdrawalRequested(msg.sender, user, token);
    }

    function recordWithdrawal(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyVaultAccount nonReentrant {
        emit WithdrawalProcessed(msg.sender, user, token, amount, fee, metadata);
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
    }

    /*

    ________
   /_______/\
   \ \    / /
 ___\ \__/_/___     /// UPGRADEABILITY ///
/____\ \______/\
\ \   \/ /   / /
 \ \  / /\  / /
  \ \/ /\ \/ /
   \_\/  \_\/

   
    */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// Initialization ///
    function initialize() external initializer {}
} 