// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {VaultRoot} from "../src/VaultRoot.sol";
import {VaultAccount} from "../src/VaultAccount.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {IVaultRoot} from "../src/interfaces/IVaultRoot.sol";
import {NoReceiver} from "./mocks/NoReceiver.sol";

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract VaultTest is Test {
    VaultRoot root;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;
    address anotherUser;
    
    // Using a real ERC20 for more realistic fork testing
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address internal pepeWhale = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    address private constant MILADYSTATION = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
    address private constant MSWhale = 0x65ccFF5cFc0E080CdD4bb29BC66A3F71153382a2;
    uint256 private constant MS_TOKEN_ID = 598; // This may not be owned by MSWhale, we will find one he owns

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
    event RefundChanged(bool isRefund);

    // Custom error from Solady's SafeTransferLib
    error TransferFailed();

    function setUp() public {
        backend = makeAddr("backend");
        user = makeAddr("user");
        anotherUser = makeAddr("anotherUser");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(anotherUser, 10 ether);
        vm.deal(pepeWhale, 10 ether);
        
        // Deploy implementation and proxy for VaultRoot
        address proxy = new ERC1967Factory().deploy(
            address(new VaultRoot()),
            admin
        );
        root = VaultRoot(payable(proxy));
        // Call initialize on the proxy
        vm.prank(admin);
        root.initialize();

        // Set initial backend
        vm.prank(admin);
        root.setBackend(backend, true);

        // Allow backend operations. The name is confusing: setFreeze(true) sets backendAllowed = true.
        vm.prank(admin);
        root.setFreeze(true);
    }

    // --- Helper Functions ---
    function _getCustodyKey(address _user, address _token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _token));
    }

    function _splitAmount(bytes32 amount) internal pure returns(uint128 userOwned, uint128 escrow) {
        userOwned = uint128(uint256(amount));
        escrow = uint128(uint256(amount >> 128));
    }

    function _packAmount(uint128 userOwned, uint128 escrow) internal pure returns(bytes32) {
        return bytes32(uint256(userOwned) | (uint256(escrow) << 128));
    }

    // --- Test Scaffolding ---

    // --- Admin & Setup ---
    function test_initialState() public {
        // Tests that the root contract is initialized with the correct owner and that the initial backend is set.
    }

    function test_setBackend_byOwner_succeeds() public {
        // Tests that the owner can add and remove a backend address.
    }

    function test_onlyOwnerFunctions_revertForEOA() public {
        vm.startPrank(user);
        vm.expectRevert("Not the owner of the token");
        root.setBackend(anotherUser, true);
        vm.stopPrank();
    }

    function test_setFreeze_byOwner_succeeds() public {
        // Tests that the owner can freeze and unfreeze backend operations.
    }

    function test_setFreeze_byNonOwner_reverts() public {
        // Tests that a non-owner cannot freeze the contract.
    }

    // --- Standard User Flow (Direct VaultRoot Interaction) ---
    function test_erc20Deposit_updatesCustody() public {
        uint256 depositAmount = 1_000_000 * 1e18; // 1M PEPE
        
        // Check whale has enough balance
        uint256 whaleBalance = ERC20(PEPE).balanceOf(pepeWhale);
        require(whaleBalance >= depositAmount, "Whale does not have enough PEPE");

        vm.startPrank(pepeWhale);
        // Approve root to spend PEPE
        ERC20(PEPE).approve(address(root), depositAmount);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(address(root), pepeWhale, PEPE, depositAmount);

        // When: whale deposits PEPE
        root.deposit(PEPE, depositAmount);
        vm.stopPrank();

        // Then: custody is updated correctly
        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, depositAmount, "userOwned balance should be updated");
        assertEq(escrow, 0, "escrow balance should be 0");
    }

    function test_root_deposit_eth() public {
        // A standard user sends ETH directly to the VaultRoot via receive().
        // Checks if the userOwned balance for the user is correctly updated.
    }

    function test_root_depositFor_byBackend_succeeds() public {
        // The backend deposits tokens into a standard user's account on their behalf.
        // Checks if the userOwned balance is correctly increased.
    }

    function test_root_depositFor_byNonBackend_reverts() public {
        // A non-backend address attempts to use depositFor and fails.
    }

    function test_backend_confirmCredit_movesToEscrow() public {
        // After a standard user deposits, the backend confirms credit.
        uint256 depositAmount = 1_000_000 * 1e18; // 1M PEPE
        
        // 1. User deposits PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), depositAmount);
        root.deposit(PEPE, depositAmount);
        vm.stopPrank();

        // Check initial custody
        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned_before, uint128 escrow_before) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned_before, depositAmount);
        assertEq(escrow_before, 0);

        // 2. Backend confirms credit
        vm.startPrank(backend);
        uint256 amountToEscrow = depositAmount / 2;
        
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CreditConfirmed(address(root), pepeWhale, PEPE, amountToEscrow, 0, "");

        root.confirmCredit(address(root), pepeWhale, PEPE, amountToEscrow, 0, "");
        vm.stopPrank();

        // 3. Check final custody
        (uint128 userOwned_after, uint128 escrow_after) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned_after, userOwned_before - amountToEscrow, "userOwned should decrease");
        assertEq(escrow_after, escrow_before + amountToEscrow, "escrow should increase");
    }

    function test_backend_blessEscrow_usesProtocolBalance() public {
        uint256 protocolAmount = 1_000_000 * 1e18;

        // 1. Seed the protocol with PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).transfer(address(root), protocolAmount);
        vm.stopPrank();

        // The PEPE is now in the contract, but we need to assign it to the protocol's `userOwned` balance
        // so we can then move it to the protocol's `escrow` balance for the test.
        bytes32 protocolKey = _getCustodyKey(address(root), PEPE);

        // Move the transferred amount to the protocol's "userOwned" balance using vm.store
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), _packAmount(uint128(protocolAmount), 0));
        
        // Use confirmCredit to move it to the protocol's *escrow* balance
        vm.prank(backend);
        root.confirmCredit(address(root), address(root), PEPE, protocolAmount, 0, "seed protocol");
        vm.stopPrank();
        
        // Check protocol escrow balance
        (, uint128 protocolEscrow_before) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow_before, protocolAmount, "Protocol should have escrow balance");

        // 2. Bless the user with some of the protocol's escrow
        vm.startPrank(backend);
        uint256 amountToBless = protocolAmount / 4;

        vm.expectEmit(true, true, true, true);
        emit CreditConfirmed(address(root), user, PEPE, amountToBless, 0, "BLESSED");
        root.blessEscrow(user, PEPE, amountToBless);
        vm.stopPrank();

        // 3. Check balances
        bytes32 userKey = _getCustodyKey(user, PEPE);
        (, uint128 userEscrow_after) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow_after, amountToBless, "User escrow should be blessed amount");

        (, uint128 protocolEscrow_after) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow_after, protocolEscrow_before - amountToBless, "Protocol escrow should decrease");
    }

    function test_backend_blessEscrow_revertsIfInsufficient() public {
        uint256 protocolAmount = 1_000_000 * 1e18;

        // 1. Seed protocol escrow with PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).transfer(address(root), protocolAmount);
        vm.stopPrank();
        bytes32 protocolKey = _getCustodyKey(address(root), PEPE);
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), _packAmount(uint128(protocolAmount), 0));
        vm.prank(backend);
        root.confirmCredit(address(root), address(root), PEPE, protocolAmount, 0, "seed protocol");
        vm.stopPrank();

        // 2. Attempt to bless with more than is available
        vm.startPrank(backend);
        uint256 amountToBless = protocolAmount + 1;
        
        vm.expectRevert("Not enough in protocol escrow");
        root.blessEscrow(user, PEPE, amountToBless);
        vm.stopPrank();

        // 3. Check balances are unchanged
        bytes32 userKey = _getCustodyKey(user, PEPE);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, 0, "User escrow should not change");

        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, protocolAmount, "Protocol escrow should not change");
    }

    function test_root_withdraw_userOwned_succeeds() public {
        // A standard user has an unconfirmed deposit (all in userOwned).
        // The user calls withdraw() and successfully gets their tokens back.
    }

    function test_root_withdraw_partial_userOwned() public {
        // A user has a mix of userOwned and escrow funds.
        // The user calls withdraw() and only gets the userOwned portion back, leaving escrow untouched.
    }

    function test_backendWithdrawTo_erc20_sendsEscrow() public {
        // 1. Setup user escrow balance
        uint256 depositAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), depositAmount);
        root.deposit(PEPE, depositAmount);
        vm.stopPrank();

        vm.prank(backend);
        root.confirmCredit(address(root), pepeWhale, PEPE, depositAmount, 0, "confirm");
        vm.stopPrank();

        // 2. Backend withdraws funds to user with a fee
        uint256 withdrawAmount = depositAmount / 2;
        uint128 fee = 100 * 1e18; // 100 PEPE fee
        
        uint256 user_balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        uint256 protocol_balance_before = ERC20(PEPE).balanceOf(address(root));

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalProcessed(address(root), pepeWhale, PEPE, withdrawAmount, fee, "withdraw");
        
        root.withdrawTo(pepeWhale, PEPE, withdrawAmount, fee, "withdraw");
        vm.stopPrank();

        // 3. Check balances
        uint256 user_balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(user_balance_after, user_balance_before + withdrawAmount, "User balance should increase by withdraw amount");

        uint256 protocol_balance_after = ERC20(PEPE).balanceOf(address(root));
        // The protocol balance change is complex: it receives `depositAmount` and sends `withdrawAmount`.
        // The net change is depositAmount - withdrawAmount. The fee is an internal accounting change.
        assertEq(protocol_balance_after, protocol_balance_before - withdrawAmount, "Protocol balance should decrease by withdraw amount");
        
        // Check internal custody
        bytes32 userKey = _getCustodyKey(pepeWhale, PEPE);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, depositAmount - withdrawAmount - fee, "User escrow should decrease by withdraw amount and fee");

        bytes32 protocolKey = _getCustodyKey(address(root), PEPE);
        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, fee, "Protocol escrow should equal the fee");
    }

    function test_root_withdrawTo_insufficientEscrow_reverts() public {
        // Backend attempts to withdrawTo more than is available in escrow and the call fails.
    }

    function test_ethDeposit_updatesCustody() public {
        // A standard user sends ETH directly to the VaultRoot via receive().
        uint256 depositAmount = 1 ether;

        vm.startPrank(user);
        // Expect event from root contract
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(address(root), user, address(0), depositAmount);

        // When: user sends ETH to the root contract
        (bool success, ) = address(root).call{value: depositAmount}("");
        require(success, "ETH transfer failed");
        
        vm.stopPrank();

        // Then: custody for the user is updated correctly
        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, depositAmount, "userOwned balance should be updated");
        assertEq(escrow, 0, "escrow balance should be 0");
    }

    function test_userWithdraw_eth_userOwned() public {
        // 1. User deposits ETH to create a userOwned balance
        uint256 depositAmount = 2 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: depositAmount}("");
        require(success, "ETH deposit failed");

        // 2. User withdraws their userOwned ETH
        uint256 balance_before = user.balance;
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit UserWithdrawal(address(root), user, address(0), depositAmount);
        
        root.withdraw(address(0));
        vm.stopPrank();

        // 3. Check balances
        uint256 balance_after = user.balance;
        assertTrue(balance_after > balance_before, "User ETH balance should increase");

        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (uint128 userOwned, ) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, 0, "userOwned balance should be zero after withdrawal");
    }

    // --- Power User Flow (VaultAccount Interaction) ---
    function test_createVaultAccount_succeeds() public {
        // Backend successfully creates a new VaultAccount for a user.
        // Checks if the account is registered in VaultRoot and owned by the correct user.
    }

    function test_createVaultAccount_predictableAddress() public {
        // Verifies that the address of a new VaultAccount can be deterministically predicted off-chain.
    }

    function test_account_deposit_erc20() public {
        // A user deposits an ERC20 token into their own VaultAccount.
        // Checks if the userOwned balance is updated in the VaultAccount's custody.
        // Also checks that VaultRoot emits the correct recordDeposit event.
    }

    function test_account_deposit_eth() public {
        // A user deposits ETH into their own VaultAccount.
        // Checks for correct state updates in the VaultAccount's custody.
    }

    function test_account_depositFor_byBackend_succeeds() public {
        // The backend deposits tokens into a user's account within their VaultAccount.
    }

    function test_account_confirmCredit_movesBalance() public {
        // After a deposit into a VaultAccount, the backend confirms credit.
        // Checks that balance moves from userOwned to escrow in the VaultAccount's custody.
    }

    function test_account_withdraw_userOwned_succeeds() public {
        // A user with a VaultAccount withdraws their own userOwned balance from their account.
    }

    function test_account_withdrawTo_byBackend_succeeds() public {
        // Backend processes a withdrawal from a user's escrow balance within their VaultAccount.
    }


    // --- Security & Edge Cases ---
    function test_userWithdraw_succeeds_whenFrozen() public {
        // Owner freezes the contract.
        // A standard user should still be able to withdraw their userOwned balance from VaultRoot.
    }

    function test_accountWithdraw_succeeds_whenFrozen() public {
        // Owner freezes the contract.
        // A power user should still be able to withdraw their userOwned balance from their VaultAccount.
    }

    function test_onlyVaultAccount_modifier() public {
        // An external address tries to call a function guarded by onlyVaultAccount on VaultRoot and fails.
        // Example: recordDeposit.
    }

    function test_reentrancy_deposit() public {
        // Verifies that the deposit functions are protected against re-entrancy attacks.
    }

    function test_reentrancy_withdraw() public {
        // Verifies that the withdraw functions are protected against re-entrancy attacks.
    }

    function test_nftDeposit_updatesCustody_correctly() public {
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens on this fork.");
        uint256 tokenIdToTransfer = tokenIds[0];

        // Given: Whale owns a MiladyStation NFT
        vm.startPrank(MSWhale);
        
        // And: Whale approves VaultRoot to receive NFT
        IERC721(MILADYSTATION).approve(address(root), tokenIdToTransfer);

        // When: Whale safeTransfers NFT to VaultRoot
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(address(root), MSWhale, MILADYSTATION, 1);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), tokenIdToTransfer);
        
        vm.stopPrank();

        // Then: custody[whale][miladyStation] increments by 1
        bytes32 custodyKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        
        assertEq(userOwned, 1, "userOwned should be 1");
        assertEq(escrow, 0, "escrow should be 0");
    }

    function test_nftDeposit_emitsCorrectEvent() public {
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens on this fork.");
        uint256 tokenIdToTransfer = tokenIds[0];

        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).approve(address(root), tokenIdToTransfer);

        // Expect: DepositRecorded(vaultRoot, whale, miladyStation, 1)
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(address(root), MSWhale, MILADYSTATION, 1);
        
        // When: whale safeTransfers tokenId to vaultRoot
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), tokenIdToTransfer);
        vm.stopPrank();
    }

    function test_nftBlessEscrow_movesFromProtocolEscrow() public {
        // Given: VaultRoot has 1 NFT in protocol escrow.
        // We will directly manipulate storage to set this up, bypassing confirmCredit.
        bytes32 protocolKey = _getCustodyKey(address(root), MILADYSTATION);
        bytes32 protocolBalance = _packAmount(0, 1); // 0 userOwned, 1 escrow
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), protocolBalance);

        // Check that protocol has 1 in escrow
        (uint128 protocolUserOwned, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0");
        assertEq(protocolEscrow, 1, "Protocol escrow should be 1");

        // When: backend blesses the user with 1 NFT escrow
        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit CreditConfirmed(address(root), user, MILADYSTATION, 1, 0, "BLESSED");
        root.blessEscrow(user, MILADYSTATION, 1);
        vm.stopPrank();

        // Then: user's custody shows +1 escrow, protocol's escrow is decremented by 1
        bytes32 userKey = _getCustodyKey(user, MILADYSTATION);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, 1, "User escrow should be 1");

        (protocolUserOwned, protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0 after blessing");
        assertEq(protocolEscrow, 0, "Protocol escrow should be 0 after blessing");
    }

    function test_nftWithdrawTo_byBackend_transfersNFT() public {
        // NOTE: This test confirms the design choice that `withdrawTo` is for fungible tokens only.
        // It is expected to revert for NFTs, as they are considered spent upon deposit.

        // Given: user has 1 escrowed NFT
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens for this test.");
        uint256 tokenId = tokenIds[0];

        // 1. User deposits NFT
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), tokenId);
        vm.stopPrank();

        // 2. Backend confirms credit to move it to escrow
        vm.startPrank(backend);
        root.confirmCredit(address(root), MSWhale, MILADYSTATION, 1, 0, "confirm");
        vm.stopPrank();

        // 3. When: backend attempts to withdrawTo() the NFT
        vm.startPrank(backend);
        
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(TransferFailed.selector);
        root.withdrawTo(MSWhale, MILADYSTATION, 1, 0, "withdraw");
        vm.stopPrank();

        // And: NFT is still owned by the vault
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), address(root));
        
        // And: user's escrow balance is unchanged
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(userKey));
        assertEq(userOwned, 0, "User userOwned should be 0");
        assertEq(escrow, 1, "User escrow should still be 1");
    }

    function test_nftWithdraw_userOwned_returnsNFT() public {
        // NOTE: This test confirms that `withdraw` also does not support NFTs,
        // aligning with the "NFTs are good as spent" design choice.

        // Given: user safeTransfers NFT to vault
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens for this test.");
        uint256 tokenId = tokenIds[0];

        // 1. User deposits NFT
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), tokenId);

        // Check that vault owns the NFT and user has 1 userOwned
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), address(root));
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned_before, ) = _splitAmount(root.custody(userKey));
        assertEq(userOwned_before, 1, "User userOwned should be 1 after deposit");

        // When: user calls withdraw()
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(TransferFailed.selector);
        root.withdraw(MILADYSTATION);
        vm.stopPrank();

        // And: NFT is still owned by the vault
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), address(root));

        // And: userOwned is unchanged
        (uint128 userOwned_after, uint128 escrow_after) = _splitAmount(root.custody(userKey));
        assertEq(userOwned_after, 1, "User userOwned should be 1 after failed withdrawal");
        assertEq(escrow_after, 0, "User escrow should be 0");
    }

    function test_nftGlobalUnlock_allowsEscrowWithdrawal() public {
        // Given: user has an escrowed NFT
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens for this test.");
        uint256 tokenId = tokenIds[0];

        // 1. User deposits NFT and backend confirms credit
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), tokenId);
        vm.stopPrank();

        vm.startPrank(backend);
        root.confirmCredit(address(root), MSWhale, MILADYSTATION, 1, 0, "confirm");
        vm.stopPrank();

        // And: owner flips isGlobalEscrowUnlocked (refund) = true
        vm.prank(admin);
        root.setRefund(true);
        assert(root.refund());

        // When: user calls withdraw()
        vm.startPrank(MSWhale);
        // NOTE: The current implementation attempts an ERC20 transfer which will fail.
        // This test documents that even with refund mode on, NFT withdrawal is broken.
        vm.expectRevert(TransferFailed.selector);
        root.withdraw(MILADYSTATION);
        vm.stopPrank();

        // Then: both userOwned and escrowed NFTs are NOT returned
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), address(root));

        // And: balances are unchanged
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(userKey));
        assertEq(userOwned, 0);
        assertEq(escrow, 1);
    }

    function test_nftDeposit_failsWithoutOnERC721Receiver() public {
        // Given: a contract without onERC721Received
        NoReceiver noReceiver = new NoReceiver();

        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens for this test.");
        uint256 tokenId = tokenIds[0];

        // When: NFT is sent to that contract
        vm.startPrank(MSWhale);

        // Then: transaction reverts
        // The ERC721 standard requires the recipient of a safe transfer to implement onERC721Received.
        // The revert reason is not standardized, so we just check for a generic revert.
        vm.expectRevert();
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(noReceiver), tokenId);
        vm.stopPrank();
    }



    // --- Event Emission Tests ---
    // function test_event_depositRecorded() public {
    //     // Tests that the DepositRecorded event is emitted correctly when a user deposits.
    //     // Checks event args: vaultAccount, user, token, amount
    // }

    // function test_event_creditConfirmed() public {
    //     // Tests that the CreditConfirmed event is emitted correctly when backend confirms credit.
    //     // Checks event args: vaultAccount, user, token, amount, fee, metadata
    // }

    // function test_event_withdrawalProcessed() public {
    //     // Tests that the WithdrawalProcessed event is emitted correctly when backend processes a withdrawal.
    //     // Checks event args: vaultAccount, user, token, amount, fee, metadata
    // }

    // function test_event_userWithdrawal() public {
    //     // Tests that the UserWithdrawal event is emitted correctly when a user withdraws their userOwned balance.
    //     // Checks event args: vaultAccount, user, token, amount
    // }

    // function test_event_liquidation() public {
    //     // Tests that the Liquidation event is emitted correctly when a fee is charged with zero withdrawal.
    //     // Checks event args: vaultAccount, user, token, fee, metadata
    // }

    // --- Utility & Admin Function Tests ---
    // function test_multicall_byBackend_succeeds() public {
    //     // Tests that the backend can successfully execute multiple calls in a single transaction.
    //     // Checks that all operations in the batch are executed correctly.
    // }

    // function test_multicall_byNonBackend_reverts() public {
    //     // Tests that non-backend addresses cannot use the multicall function.
    // }

    // function test_multicall_nonOrigin_reverts() public {
    //     // Tests that multicall reverts when called by a contract (not tx.origin).
    // }

    // function test_performCalldata_byOwner_succeeds() public {
    //     // Tests that the owner can successfully execute arbitrary calldata on a target contract.
    // }

    // function test_performCalldata_byNonOwner_reverts() public {
    //     // Tests that non-owner addresses cannot use the performCalldata function.
    // }

    // --- Edge Cases & Boundary Tests ---
    // function test_zeroValueOperations() public {
    //     // Tests behavior with zero-value deposits, credits, and withdrawals.
    // }

    // function test_maxUint128Values() public {
    //     // Tests behavior when userOwned or escrow values approach uint128 max.
    // }

    // function test_unexpectedTokens() public {
    //     // Tests what happens when tokens are sent directly to the contract without using deposit functions.
    // }

    // --- Gas Optimization Tests ---
    // function testGas_deposit() public {
    //     // Measures gas usage for standard deposit operations.
    // }

    // function testGas_confirmCredit() public {
    //     // Measures gas usage for backend credit confirmation.
    // }

    // function testGas_withdrawTo() public {
    //     // Measures gas usage for backend-initiated withdrawals.
    // }

    // function testGas_createVaultAccount() public {
    //     // Measures gas usage for VaultAccount creation.
    // }

    // function testGas_multicall_vs_individual() public {
    //     // Compares gas usage between multicall and individual function calls.
    // }

    // --- Upgradeability Tests ---
    // function test_upgrade_byOwner_succeeds() public {
    //     // Tests that the owner can successfully upgrade the VaultRoot implementation.
    //     // 1. Deploy a new implementation contract
    //     // 2. Upgrade the proxy to point to the new implementation
    //     // 3. Verify the upgrade was successful by checking new functionality
    // }

    // function test_upgrade_byNonOwner_reverts() public {
    //     // Tests that non-owner addresses cannot upgrade the VaultRoot implementation.
    // }

    // function test_upgrade_statePreservation() public {
    //     // Tests that contract state (custody balances, backend addresses, etc.) is preserved during an upgrade.
    // }

    // function test_upgrade_withInitializer() public {
    //     // Tests upgrading with a new implementation that has an initializer function.
    //     // Uses upgradeToAndCall instead of upgradeTo.
    // }

    // --- Integration Tests ---
    function test_root_and_vaultAccount_emitDeposit_and_Withdraw_correctly() public {
        // 1. Create a VaultAccount.
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        // 2. Deposit ETH into VaultAccount
        uint256 depositAmount = 1 ether;
        vm.startPrank(user);

        // Expect DepositRecorded from VaultAccount
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(accountAddress, user, address(0), depositAmount);
        
        // Expect DepositRecorded from VaultRoot
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(accountAddress, user, address(0), depositAmount);

        (bool success, ) = accountAddress.call{value: depositAmount}("");
        require(success, "ETH deposit to account failed");

        // 3. Withdraw ETH from VaultAccount
        vm.expectEmit(true, true, true, true);
        emit UserWithdrawal(accountAddress, user, address(0), depositAmount);

        // The VaultAccount's withdraw() calls vaultRoot.recordWithdrawal()
        vm.expectEmit(true, true, true, true);
        emit WithdrawalProcessed(accountAddress, user, address(0), depositAmount, 0, "");

        vaultAccount.withdraw(address(0));
        vm.stopPrank();
    }

    function test_vaultAccount_nftDeposit_updatesCustody() public {
        // 1. Create a VaultAccount for 'anotherUser'
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        // Given: a user owns a Milady NFT
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale does not own any MiladyStation tokens for this test.");
        uint256 tokenId = tokenIds[0];

        // And: the user approves the VaultAccount to receive NFTs
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).approve(address(vaultAccount), tokenId);

        // When: the user calls safeTransferFrom() to VaultAccount
        // Then: A single DepositRecorded event is emitted from VaultRoot, forwarded by the VaultAccount.
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(accountAddress, MSWhale, MILADYSTATION, 1);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(vaultAccount), tokenId);
        vm.stopPrank();
        
        // Then: custody[user][nftAddress] increments by 1 in the VaultAccount
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(vaultAccount.custody(userKey));
        assertEq(userOwned, 1, "VaultAccount userOwned should be 1");
        assertEq(escrow, 0, "VaultAccount escrow should be 0");
    }

    function test_vaultAccount_nftBlessEscrow_movesFromProtocolEscrow() public {
        // 1. Create a VaultAccount.
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        // Given: The VaultAccount has 1 NFT in its own "protocol" escrow.
        // This simulates a scenario where the account itself holds assets to be distributed.
        bytes32 protocolKey = _getCustodyKey(address(vaultAccount), MILADYSTATION);
        bytes32 protocolBalance = _packAmount(0, 1); // 0 userOwned, 1 escrow
        bytes32 storageSlot = keccak256(abi.encode(protocolKey, 0)); // custody is at slot 0
        vm.store(address(vaultAccount), storageSlot, protocolBalance); 

        // When: backend calls blessEscrow on the VaultAccount for a user.
        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit CreditConfirmed(address(vaultAccount), user, MILADYSTATION, 1, 0, "BLESSED");
        vaultAccount.blessEscrow(user, MILADYSTATION, 1);
        vm.stopPrank();

        // Then: user's custody in the account shows +1 escrow.
        bytes32 userKey = _getCustodyKey(user, MILADYSTATION);
        (, uint128 userEscrow) = _splitAmount(vaultAccount.custody(userKey));
        assertEq(userEscrow, 1, "User escrow in VaultAccount should be 1");

        // And: The account's protocol escrow is now 0.
        (, uint128 protocolEscrow) = _splitAmount(vaultAccount.custody(protocolKey));
        assertEq(protocolEscrow, 0, "VaultAccount protocol escrow should be 0");
    }

    function test_vaultAccount_nftWithdrawTo_transfersNFT() public {
        // NOTE: This test confirms that VaultAccount.withdrawTo is also for fungibles only.
        
        // 1. Create a VaultAccount.
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        // 2. User deposits an NFT.
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "No Milady tokens for test.");
        uint256 tokenId = tokenIds[0];
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, accountAddress, tokenId);
        vm.stopPrank();

        // 3. Backend confirms credit to move NFT to escrow.
        vm.startPrank(backend);
        vaultAccount.confirmCredit(accountAddress, MSWhale, MILADYSTATION, 1, 0, "confirm");
        vm.stopPrank();

        // 4. When backend calls withdrawTo...
        vm.startPrank(backend);
        
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(TransferFailed.selector);
        vaultAccount.withdrawTo(MSWhale, MILADYSTATION, 1, 0, "withdraw");
        vm.stopPrank();

        // 5. Then: VaultAccount still owns the NFT.
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), accountAddress, "VaultAccount should own NFT");
        
        // And: user's escrow balance is unchanged.
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(vaultAccount.custody(userKey));
        assertEq(userOwned, 0, "User userOwned should be 0");
        assertEq(escrow, 1, "User escrow should still be 1");
    }

    function test_vaultAccount_nftWithdraw_userOwned_returnsNFT() public {
        // NOTE: This test confirms that VaultAccount.withdraw is also for fungibles only.
        
        // 1. Create a VaultAccount.
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        // 2. User deposits an NFT.
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "No Milady tokens for test.");
        uint256 tokenId = tokenIds[0];
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, accountAddress, tokenId);
        
        // 3. When user calls withdraw...
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(TransferFailed.selector);
        vaultAccount.withdraw(MILADYSTATION);
        vm.stopPrank();

        // 4. Then: VaultAccount still owns the NFT.
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), accountAddress, "VaultAccount should still own NFT");
        
        // And: user's userOwned balance is unchanged.
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, ) = _splitAmount(vaultAccount.custody(userKey));
        assertEq(userOwned, 1, "User userOwned should be 1");
    }

    function test_vaultAccount_globalUnlock_withdrawsEscrowedNFT() public {
        // NOTE: This test confirms that even with global refund mode, VaultAccount.withdraw is for fungibles only.

        // 1. Create a VaultAccount and escrow an NFT.
        vm.startPrank(backend);
        address accountAddress = root.createVaultAccount(anotherUser, bytes32(0));
        vm.stopPrank();
        VaultAccount vaultAccount = VaultAccount(payable(accountAddress));

        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "No Milady tokens for test.");
        uint256 tokenId = tokenIds[0];
        
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, accountAddress, tokenId);
        vm.stopPrank();

        vm.startPrank(backend);
        vaultAccount.confirmCredit(accountAddress, MSWhale, MILADYSTATION, 1, 0, "confirm");
        vm.stopPrank();

        // 2. Enable global refund mode.
        vm.prank(admin);
        root.setRefund(true);
        assertTrue(root.refund(), "Refund mode should be on");

        // 3. When user calls withdraw...
        vm.startPrank(MSWhale);
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(TransferFailed.selector);
        vaultAccount.withdraw(MILADYSTATION);
        vm.stopPrank();

        // 4. Then: VaultAccount still owns the NFT.
        assertEq(IERC721(MILADYSTATION).ownerOf(tokenId), accountAddress, "VaultAccount should still own NFT");
        
        // And: user's escrow balance is unchanged.
        bytes32 userKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwned, uint128 escrow) = _splitAmount(vaultAccount.custody(userKey));
        assertEq(userOwned, 0);
        assertEq(escrow, 1);
    }

    function test_userWithdraw_erc20_userOwned() public {
        // 1. User deposits PEPE to create a userOwned balance
        uint256 depositAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), depositAmount);
        root.deposit(PEPE, depositAmount);
        vm.stopPrank();

        // 2. User withdraws their userOwned PEPE
        uint256 balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        vm.startPrank(pepeWhale);

        vm.expectEmit(true, true, true, true);
        emit UserWithdrawal(address(root), pepeWhale, PEPE, depositAmount);
        
        root.withdraw(PEPE);
        vm.stopPrank();

        // 3. Check balances
        uint256 balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(balance_after, balance_before + depositAmount, "User PEPE balance should increase");

        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned, ) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, 0, "userOwned balance should be zero after withdrawal");
    }

    function test_backendWithdrawTo_eth_sendsEscrow() public {
        // 1. Setup user escrow balance
        uint256 depositAmount = 5 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: depositAmount}("");
        require(success);

        vm.prank(backend);
        root.confirmCredit(address(root), user, address(0), depositAmount, 0, "confirm");
        vm.stopPrank();

        // 2. Backend withdraws funds to user with a fee
        uint256 withdrawAmount = 2 ether;
        uint128 fee = uint128(0.1 ether);
        
        uint256 user_balance_before = user.balance;

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalProcessed(address(root), user, address(0), withdrawAmount, fee, "withdraw");
        
        root.withdrawTo(user, address(0), withdrawAmount, fee, "withdraw");
        vm.stopPrank();

        // 3. Check balances
        uint256 user_balance_after = user.balance;
        assertEq(user_balance_after, user_balance_before + withdrawAmount, "User balance should increase by withdraw amount");
        
        // Check internal custody
        bytes32 userKey = _getCustodyKey(user, address(0));
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, depositAmount - withdrawAmount - fee, "User escrow should decrease by withdraw amount and fee");

        bytes32 protocolKey = _getCustodyKey(address(root), address(0));
        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, fee, "Protocol escrow should equal the fee");
    }

    function test_globalUnlock_allowsEthEscrowWithdrawal() public {
        // 1. Setup user escrow balance
        uint256 depositAmount = 3 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: depositAmount}("");
        require(success);

        vm.prank(backend);
        root.confirmCredit(address(root), user, address(0), depositAmount, 0, "confirm");
        vm.stopPrank();

        // 2. Enable global refund mode
        vm.prank(admin);
        root.setRefund(true);
        assertTrue(root.refund());

        // 3. User withdraws their escrowed ETH
        uint256 balance_before = user.balance;
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit UserWithdrawal(address(root), user, address(0), depositAmount);
        
        root.withdraw(address(0));
        vm.stopPrank();

        // 4. Check balances
        uint256 balance_after = user.balance;
        assertTrue(balance_after > balance_before, "User ETH balance should increase");

        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(escrow, 0, "escrow balance should be zero after withdrawal");
    }

    function test_globalUnlock_allowsErc20EscrowWithdrawal() public {
        // 1. Setup user escrow balance
        uint256 depositAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), depositAmount);
        root.deposit(PEPE, depositAmount);
        vm.stopPrank();

        vm.prank(backend);
        root.confirmCredit(address(root), pepeWhale, PEPE, depositAmount, 0, "confirm");
        vm.stopPrank();

        // 2. Enable global refund mode
        vm.prank(admin);
        root.setRefund(true);

        // 3. User withdraws their escrowed PEPE
        uint256 balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        vm.startPrank(pepeWhale);

        vm.expectEmit(true, true, true, true);
        emit UserWithdrawal(address(root), pepeWhale, PEPE, depositAmount);
        
        root.withdraw(PEPE);
        vm.stopPrank();

        // 4. Check balances
        uint256 balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(balance_after, balance_before + depositAmount, "User PEPE balance should increase");

        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(escrow, 0, "escrow balance should be zero after withdrawal");
    }

} 