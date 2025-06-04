// SPDX-License-Identifier: MIT

/*

✅ Required Implementation Functions
📥 Deposit & Credit
function confirmCredit(address user, address token, uint256 usdAmount) external onlyBackend

💸 Withdrawals
function requestWithdrawal(address token, uint256 amount) external

function withdrawTo(address user, address token, uint256 amount, uint256 pointsBurned, uint256 usdCreditedAtDeposit) external onlyBackend

🛠 Admin & Configuration
function setcoinFeeFee(address token, uint256 feeBps) external onlyOwner

function setWithdrawalFee(uint256 feeBps) external onlyOwner

function setPointUsdRate(uint256 microUsdPerPoint) external onlyOwner

function addBackend(address account) external onlyOwner

function removeBackend(address account) external onlyOwner

🧠 Multicall Utility
function multicall(bytes[] calldata data) external onlyBackend

🔐 Arbitrary Execution (Admin-Only)
function performCalldata(bytes calldata data) external onlyOwner

🏗 Initialization
function initialize(address[] calldata tokens, address backend) external initializer

*/
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract AiCreditVault is UUPSUpgradeable, Initializable, ReentrancyGuard {

    // --- Structs ---
    struct Receipt {
        uint256 amount;
        uint256 points; // Points credited for this specific collateral
        uint256 feeBps;
    }

    // --- Constants ---
    uint256 public constant MAX_ACCEPTED_TOKENS = 6;
    address private constant MS2 = 0x98Ed411B8cf8536657c660Db8aA55D9D4bAAf820;
    address private constant CULT = 0x0000000000c5dc95539589fbD24BE07c6C14eCa4;
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address private constant MOG = 0xaaeE1A9723aaDB7afA2810263653A34bA2C21C7a;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // --- Storage ---
    mapping(address => mapping(address => Receipt)) public collateral;
    mapping(address => int256) public points; // User's global point balance
    mapping(address => mapping(address => uint256)) public reconciliation; // Timestamp of last credit confirmation
    mapping(address => uint256) public warChest;
    mapping(address => uint256) public coinFee; // token => feeBps
    mapping(address => bool) public isGoodCoin;
    address[MAX_ACCEPTED_TOKENS] public goodCoins;
    mapping(address => bool) public isStationThis; // Backend addresses

    uint256 public pointToUsdRate;

    // --- Events ---
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event CreditConfirmed(address indexed user, address indexed token, uint256 usdAmount, uint256 pointsCredited, int256 userPoints);
    event WithdrawalRequested(address indexed user, address indexed token, uint256 amount);
    event WithdrawReconciled(address indexed user, address indexed token, uint256 amount);

    // --- Modifiers ---
    modifier onlyBackend() {
        require(isStationThis[msg.sender], "Not authorized backend");
        _;
    }   

    /// @notice Restricts function access to the current owner of token MiladyStation NFT ID 598.
    /// @dev This enforces ownership via an ERC721 `ownerOf(uint256)` call, rather than OpenZeppelin's Ownable pattern.
    ///      The NFT address is hardcoded as 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0.
    ///      If the token is transferred, contract control transfers with it. 
    modifier onlyOwner() {
        (, bytes memory data) = (0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0).call(abi.encodeWithSelector(0x6352211e, 598));
        require(abi.decode(data, (address)) == msg.sender, "Not the owner of the token");
        _;
    }

    // --- Initialization ---
    function initialize(address[] calldata tokens, address backend) external initializer {
        for (uint256 i = 0; i < tokens.length && i < MAX_ACCEPTED_TOKENS; ++i) {
            goodCoins[i] = tokens[i];
            isGoodCoin[tokens[i]] = true;
        }
        isStationThis[backend] = true;

        coinFee[WETH] = 200; //2%
        coinFee[USDT] = 100; //2%
        coinFee[MOG] = 500; //5%
        coinFee[PEPE] = 500; //5%
        coinFee[CULT] = 0; //0%
        coinFee[MS2] = 0; //0% //TODO: add ms2 fee
        coinFee[address(0)] = 200; //2%
        pointToUsdRate = 337; //0.000337
    }

    // --- Deposit / Credit ---

    receive() external payable {
        Receipt storage last = collateral[msg.sender][address(0)];
        require(last.amount == 0 || last.points > 0, "CreditVault: last deposit not confirmed");
        collateral[msg.sender][address(0)] = Receipt({
            amount: msg.value,
            points: 0, // Points are 0 until confirmed by backend
            feeBps: coinFee[address(0)]
        });
        emit Deposit(msg.sender, address(0), msg.value);
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        Receipt storage last = collateral[msg.sender][token];
        // Allow deposit if it's the first one (amount == 0) OR if the last one was confirmed (points > 0)
        require(last.amount == 0 || last.points > 0, "CreditVault: last deposit not confirmed");
        require(isGoodCoin[token], "Token not accepted");

        // ERC20(token).transferFrom(msg.sender, address(this), amount);
        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);

        collateral[msg.sender][token] = Receipt({
            amount: amount,
            points: 0, // Points are 0 until confirmed by backend
            feeBps: coinFee[token]
        });
        emit Deposit(msg.sender, token, amount);
    }

    function confirmCredit(address user, address token, uint256 pointsToCredit) external onlyBackend {
        Receipt storage receiptToUpdate = collateral[user][token];
        // Ensure there was a deposit to confirm. Amount should be > 0.
        // The .points field in Receipt stores the total points credited for this specific collateral amount.
        require(receiptToUpdate.amount > 0, "CreditVault: No deposit found to confirm credit for");

        int256 oldPointsForThisReceipt = int256(receiptToUpdate.points);
        receiptToUpdate.points = pointsToCredit; // Set/update the points for this specific collateral entry

        // Update the user's global point balance by the change in points for this specific receipt
        points[user] = points[user] - oldPointsForThisReceipt + int256(pointsToCredit);

        reconciliation[user][token] = block.timestamp;

        // Calculate USD equivalent for the event based on the total points credited for this collateral
        uint256 usdEquivalent = (pointsToCredit * pointToUsdRate) / 1_000_000; // pointToUsdRate is microUSD
        emit CreditConfirmed(user, token, usdEquivalent, pointsToCredit, points[user]);
    }

    // --- Withdrawals ---
    function requestWithdrawal(address token) external nonReentrant {
        Receipt storage receipt = collateral[msg.sender][token];
        uint256 amountToWithdraw = receipt.amount;

        require(amountToWithdraw > 0, "CreditVault: No collateral to withdraw for this token");

        if (reconciliation[msg.sender][token] == 0) {
            // Deposit was never confirmed by the backend; allow immediate full withdrawal.
            // Any points in receipt.points should be 0 if never confirmed, and global points[user]
            // should not have been affected by this receipt's points yet.

            // Important: Clear the collateral record for this user and token *before* transfer.
            delete collateral[msg.sender][token];

            if (token == address(0)) {
                payable(msg.sender).transfer(amountToWithdraw);
            } else {
                ERC20(token).transfer(msg.sender, amountToWithdraw);
            }
            emit WithdrawReconciled(msg.sender, token, amountToWithdraw);
        } else {
            // Deposit was confirmed. User requests withdrawal, backend will process via withdrawTo.
            // The full amount of the collateral is signaled in the request.
            emit WithdrawalRequested(msg.sender, token, amountToWithdraw);
        }
    }

    function withdrawTo(
        address user,
        address token,
        uint256 amount, // Expected to be the full collateral amount for this user/token
        uint256 pointsBurned,
        uint256 usdCreditedAtDeposit // Assumed to be used by backend for its logic, not directly in these on-chain token calculations
    ) external onlyBackend nonReentrant {
        Receipt storage receipt = collateral[user][token];

        // Validate inputs and state
        require(receipt.amount > 0, "CreditVault: No collateral found for this user/token");
        require(receipt.amount >= amount, "CreditVault: Amount parameter does not match stored collateral");
        // if receipt.points is 0, it means confirmCredit was likely never called with points, or called with 0 points.
        // Division by zero if receipt.points is 0.
        // pointsBurned can be 0. If pointsBurned is >0, then receipt.points must have been >0.
        if (pointsBurned > 0) {
            require(points[user] > 0, "CreditVault: Collateral has no point value to burn against");
        }
        
        uint256 valueOfPointsBurnedInToken;
        if (receipt.points > 0 && receipt.points > pointsBurned) { // Avoid division by zero if receipt.points is 0 (and pointsBurned is also 0)
            valueOfPointsBurnedInToken = (receipt.amount * pointsBurned) / receipt.points;
        } else {
            // If pointsBurned is >= receipt.points (or receipt.points is 0),
            // the value of burned points converted to tokens is considered 0 for this calculation.
            // This means the user will receive their full `receipt.amount` back (less fees),
            // but `points[user]` will still be debited by the full `pointsBurned`,
            // potentially leading to a negative `points[user]` balance.
            // This behavior is highlighted in `testWithdrawToExceedsCreditShouldRevert`.
            valueOfPointsBurnedInToken = 0;
        }

        require(valueOfPointsBurnedInToken <= receipt.amount, "CreditVault: Calculated burn value exceeds collateral amount"); // Sanity check

        uint256 amountRemainingAfterUsage = receipt.amount - valueOfPointsBurnedInToken;
        uint256 feeAmount = (amountRemainingAfterUsage * receipt.feeBps) / 10000;

        require(feeAmount <= amountRemainingAfterUsage, "CreditVault: Fee exceeds remaining amount after usage"); // Should prevent underflow

        uint256 actualAmountToTransferToUser = amountRemainingAfterUsage - feeAmount;
        uint256 totalValueToWarChest = valueOfPointsBurnedInToken + feeAmount;

        // Effects
        points[user] -= int256(pointsBurned); // Update user's global point balance
        if (totalValueToWarChest > 0) { // Only update warchest if there's something to add
             warChest[token] += totalValueToWarChest;
        }

        delete collateral[user][token];
        delete reconciliation[user][token];

        // Interactions
        if (actualAmountToTransferToUser > 0) {
            if (token == address(0)) {
                payable(user).transfer(actualAmountToTransferToUser);
            } else {
                ERC20(token).transfer(user, actualAmountToTransferToUser);
            }
        }

        emit WithdrawReconciled(user, token, actualAmountToTransferToUser);
    }

    // --- Admin Config ---
    function setCoinFee(address token, uint256 feeBps) external onlyOwner {
        coinFee[token] = feeBps;
    }

    function setPointUsdRate(uint256 microUsdPerPoint) external onlyOwner {
        pointToUsdRate = microUsdPerPoint;
    }

    function setStationThis(address account, bool isStation) external onlyOwner {
        isStationThis[account] = isStation;
    }

    // --- Utility ---
    function multicall(bytes[] calldata data) external onlyBackend {
        require(msg.sender == tx.origin, "Multicall can only be called by the origin");
        for (uint256 i = 0; i < data.length; ++i) {
            (bool success, ) = address(this).delegatecall(data[i]);
            require(success, "Multicall failed");
        }
    }

    function performCalldata(bytes calldata data) external onlyOwner payable {
        // --- Pre-execution snapshot --- 
        address[MAX_ACCEPTED_TOKENS + 1] memory tokens_to_monitor;
        uint256 monitor_count = 0;

        // Add ETH to monitor list
        tokens_to_monitor[monitor_count++] = address(0);

        // Add unique, non-zero goodCoins to monitor list
        for (uint256 i = 0; i < MAX_ACCEPTED_TOKENS; ++i) {
            address current_good_coin = goodCoins[i];
            if (current_good_coin != address(0)) {
                bool is_new_token = true;
                for (uint256 j = 0; j < monitor_count; ++j) { // Check if already added (e.g. if goodCoin[i] was ETH or a duplicate)
                    if (tokens_to_monitor[j] == current_good_coin) {
                        is_new_token = false;
                        break;
                    }
                }
                if (is_new_token) {
                    // Ensure we don't exceed array bounds, though unlikely with MAX_ACCEPTED_TOKENS = 6
                    if (monitor_count < tokens_to_monitor.length) {
                        tokens_to_monitor[monitor_count++] = current_good_coin;
                    } else {
                        revert("performCalldata: Exceeded token monitoring capacity");
                    }
                }
            }
        }

        uint256[] memory balances_before = new uint256[](monitor_count);
        uint256[] memory war_chests_before = new uint256[](monitor_count);

        for (uint256 i = 0; i < monitor_count; ++i) {
            address token = tokens_to_monitor[i];
            if (token == address(0)) {
                balances_before[i] = address(this).balance;
            } else {
                balances_before[i] = ERC20(token).balanceOf(address(this));
            }
            war_chests_before[i] = warChest[token];
        }

        // --- Execute calldata --- 
        (bool success, ) = address(this).call(data);
        require(success, "performCalldata: Execution failed");

        // --- Post-execution checks --- 
        for (uint256 i = 0; i < monitor_count; ++i) {
            address token = tokens_to_monitor[i];
            uint256 balance_after;

            if (token == address(0)) {
                balance_after = address(this).balance;
            } else {
                balance_after = ERC20(token).balanceOf(address(this));
            }

            // Check: Amount sent out by the call must not exceed the war_chest_before[token].
            // This is equivalent to: (balances_before[i] - war_chests_before[i]) <= balance_after
            // which means the non-war-chest funds from before must be covered by the balance after.
            if (balance_after < balances_before[i]) { // Tokens were sent out
                uint256 amount_sent_out = balances_before[i] - balance_after;
                require(amount_sent_out <= war_chests_before[i], "performCalldata: War chest funds compromised by call");
                // Update warChest to reflect the expenditure
                warChest[token] = war_chests_before[i] - amount_sent_out;
            }
            // If balance_after >= balances_before[i], it means no net tokens were sent out for this specific token
            // (either tokens were received, or the balance is unchanged).
            // In this scenario, the warChest for this token is not decremented by this spend check.
            // The warChest is not intended to be *incremented* by arbitrary inflows via performCalldata;
            // it is primarily funded by fees and burned points from withdrawTo.
        }
    }

    // --- Upgrade Authorization ---
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}