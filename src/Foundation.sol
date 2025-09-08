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
import {Keep} from "./Keep.sol";

interface ICreate2Factory {
    function deploy(bytes calldata _initCode, bytes32 _salt) external returns (address);
}

contract Foundation is Keep, UUPSUpgradeable, Initializable, ReentrancyGuard {

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

    // custody mapping now lives in Keep
    mapping(address => bool) public isCharteredFund;
    mapping(address => bool) public isMarshal;
    bool public marshalFrozen = false;
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
    event Liquidation(address indexed fundAddress, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event MarshalStatusChanged(address indexed marshal, bool isAuthorized);
    event OperatorFreeze(bool isFrozen);
    event RefundChanged(bool isRefund);
    event Donation(address indexed funder, address indexed token, uint256 amount, bool isNFT, bytes32 metadata);

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
        if(abi.decode(data, (address)) != msg.sender) revert Auth();
        _;
    }

    modifier onlyMarshal() {
        if(!isMarshal[msg.sender]) revert Auth();
        if(marshalFrozen) revert Auth();
        _;
    }

    modifier onlyCharteredFund() {
        if(!isCharteredFund[msg.sender]) revert Auth();
        _;
    }
    
    /*
      ____
     /\\___\\  /// HELPER FUNCTIONS ///
    /\\ \\___\\
    \\ \\/ / /
     \\/_/_/ 

    */
    // helper functions now reside in Keep

    /*
       ______
      /\\_____\\     
     _\\ \\__/_/_   
    /\\_\\ \\_____\\  /// OWNER & OPERATOR MANAGEMENT ///
    \\ \\ \\/ / / /   
     \\ \\/ /\\/ /   
      \\/_/\\/_/    

    */

    function setMarshal(address _marshal, bool _isAuthorized) external onlyOwner {
        isMarshal[_marshal] = _isAuthorized;
        emit MarshalStatusChanged(_marshal, _isAuthorized);
    }

    function setFreeze(bool isFrozen) external onlyOwner {
        marshalFrozen = isFrozen;
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

    function charterFund(address _owner, bytes32 _salt) external onlyMarshal returns (address) {
        bytes memory bytecode = type(CharteredFund).creationCode;
        bytes memory constructorArgs = abi.encode(address(this), _owner);
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);
        
        address fund;
        assembly {
            fund := create2(0, add(initCode, 0x20), mload(initCode), _salt)
        }
        if(fund == address(0)) revert Fail();

        isCharteredFund[fund] = true;
        emit FundChartered(fund, _owner, _salt);
        return fund;
    }

    function multicall(bytes[] calldata data) external onlyMarshal {
        if(msg.sender != tx.origin) revert Auth();
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, ) = address(this).delegatecall(data[i]);
            if(!success) revert Fail();
        }
    }
    
    function performCalldata(address target, bytes calldata data) external payable onlyOwner {
        (bool success, ) = target.call{value: msg.value}(data);
        if(!success) revert Fail();
    }

    function allocate(address user, address token, uint256 amount) external onlyMarshal {
        if(!_allocate(user, token, amount)) revert Math();
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
        _receiveETH(msg.sender, msg.value);
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
        _handleERC721(msg.sender, from);
        emit ContributionRecorded(address(this), from, msg.sender, 1);
        return 0x150b7a02;
    }

    function contribute(address token, uint256 amount) external nonReentrant {
        _contributeFor(msg.sender, msg.sender, token, amount);
        emit ContributionRecorded(address(this), msg.sender, token, amount);
    }

    /**
     * @notice Sponsor deposits `amount` of `token` on behalf of `user`.
     * @dev Anyone can act as a sponsor; tokens are pulled from `msg.sender`.
     */
    function contributeFor(address user, address token, uint256 amount) external nonReentrant {
        _contributeFor(msg.sender, user, token, amount);
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
        (RescissionOutcome outcome, uint128 amt) = _requestRescission(msg.sender, token, refund);
        if (outcome == RescissionOutcome.UserOwnedWithdrawn || outcome == RescissionOutcome.EscrowRefunded) {
            emit ContributionRescinded(address(this), msg.sender, token, amt);
        } else {
            emit RescissionRequested(address(this), msg.sender, token);
        }
    }

    function remit(address user, address token, uint256 amount, uint128 fee, bytes calldata metadata) external onlyMarshal nonReentrant {
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

    function commit(address fundAddress, address user, address token, uint256 escrowAmount, uint128 fee, bytes calldata metadata) external onlyMarshal nonReentrant {
        (bool ok, uint128 ownedBefore) = _commitEscrow(user, token, escrowAmount);
        if (!ok) revert Math();

        if (fee > 0) {
            uint256 remainingOwned = ownedBefore - escrowAmount;
            if (fee > remainingOwned) revert Math();
            bytes32 accountKey = _getCustodyKey(address(this), token);
            (, uint128 accountEscrow) = _splitAmount(custody[accountKey]);
            custody[accountKey] = _packAmount(0, accountEscrow + fee);
        }
        emit CommitmentConfirmed(fundAddress, user, token, escrowAmount, fee, metadata);
    }

    function donate(address token, uint256 amount, bytes32 metadata, bool isNFT) external payable nonReentrant {
        if (token == address(0) && msg.value < amount) revert Math();
        _donate(msg.sender, token, amount, isNFT);
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