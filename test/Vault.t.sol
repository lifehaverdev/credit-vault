// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {VaultRoot} from "../src/VaultRoot.sol";
import {VaultAccount} from "../src/VaultAccount.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
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

    function test_setBackend_byNonOwner_reverts() public {
        // Tests that a non-owner cannot change backend addresses.
    }

    function test_setFreeze_byOwner_succeeds() public {
        // Tests that the owner can freeze and unfreeze backend operations.
    }

    function test_setFreeze_byNonOwner_reverts() public {
        // Tests that a non-owner cannot freeze the contract.
    }

    // --- Standard User Flow (Direct VaultRoot Interaction) ---
    function test_root_deposit_erc20() public {
        // A standard user deposits an ERC20 token directly into the VaultRoot.
        // Checks if the userOwned balance for the user is correctly updated in root's custody.
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

    function test_root_confirmCredit_movesBalance() public {
        // After a standard user deposits, the backend confirms credit.
        // Checks that the balance correctly moves from userOwned to escrow in root's custody.
    }

    function test_root_withdraw_userOwned_succeeds() public {
        // A standard user has an unconfirmed deposit (all in userOwned).
        // The user calls withdraw() and successfully gets their tokens back.
    }

    function test_root_withdraw_partial_userOwned() public {
        // A user has a mix of userOwned and escrow funds.
        // The user calls withdraw() and only gets the userOwned portion back, leaving escrow untouched.
    }

    function test_root_withdrawTo_byBackend_succeeds() public {
        // A user has funds in escrow. The backend processes a withdrawal.
        // Checks that the user receives the correct amount and the fee is handled correctly.
    }

    function test_root_withdrawTo_insufficientEscrow_reverts() public {
        // Backend attempts to withdrawTo more than is available in escrow and the call fails.
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
    function test_backendOperations_revert_whenFrozen() public {
        // Owner freezes the contract.
        // All functions with the onlyBackend modifier should revert.
    }

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
        // Given: VaultRoot has an NFT in its own custody, which we'll move to escrow.
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length >= 1, "Whale needs at least 1 NFT for this test.");
        uint256 protocolNftId = tokenIds[0];

        // 1. Transfer an NFT to the VaultRoot to be owned by the protocol.
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, address(root), protocolNftId);
        vm.stopPrank();

        // 2. Backend confirms credit for the protocol itself, moving the NFT to protocol escrow.
        vm.startPrank(backend);
        root.confirmCredit(address(root), address(root), MILADYSTATION, 1, 0, "");
        vm.stopPrank();

        // Check that protocol has 1 in escrow
        bytes32 protocolKey = _getCustodyKey(address(root), MILADYSTATION);
        (uint128 protocolUserOwned, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0");
        assertEq(protocolEscrow, 1, "Protocol escrow should be 1");

        // 3. Backend blesses the user with 1 NFT escrow
        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit CreditConfirmed(address(root), user, MILADYSTATION, 1, 0, "BLESSED");
        root.blessEscrow(user, MILADYSTATION, 1);
        vm.stopPrank();

        // 4. Then: user's custody shows +1 escrow, protocol's escrow is decremented by 1
        bytes32 userKey = _getCustodyKey(user, MILADYSTATION);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, 1, "User escrow should be 1");

        (protocolUserOwned, protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0 after blessing");
        assertEq(protocolEscrow, 0, "Protocol escrow should be 0 after blessing");
    }

    function test_nftWithdrawTo_byBackend_transfersNFT() public {
        // Given: user has 1 escrowed NFT
        // When: backend withdrawTo() user with amount = 1, token = miladyStation
        // Then: NFT is transferred from vaultRoot to user
        // And: custody[user][miladyStation] escrow is decremented
    }

    function test_nftWithdraw_userOwned_returnsNFT() public {
        // Given: user safeTransfers NFT to vault
        // When: user calls withdraw()
        // Then: NFT is returned to user
        // And: userOwned is reset to 0
    }

    function test_nftGlobalUnlock_allowsEscrowWithdrawal() public {
        // Given: user has escrowed NFTs
        // And: owner flips isGlobalEscrowUnlocked = true
        // When: user calls withdraw()
        // Then: both userOwned and escrowed NFTs are returned
    }

    function test_nftDeposit_failsWithoutOnERC721Receiver() public {
        // Given: a contract without onERC721Received
        // When: NFT is sent to that contract
        // Then: transaction reverts
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
    // function test_fullLifecycle_standardUser() public {
    //     // Tests a complete lifecycle for a standard user:
    //     // 1. Deposit
    //     // 2. Credit confirmation
    //     // 3. Partial withdrawal
    //     // 4. Additional deposit
    //     // 5. Full withdrawal
    // }

    // function test_fullLifecycle_powerUser() public {
    //     // Tests a complete lifecycle for a power user with a VaultAccount:
    //     // 1. VaultAccount creation
    //     // 2. Deposit
    //     // 3. Credit confirmation
    //     // 4. Partial withdrawal
    //     // 5. Additional deposit
    //     // 6. Full withdrawal
    // }

    function test_vaultAccount_nftDeposit_updatesCustody() public {
        // Given: a user owns a Milady NFT
        // And: the user approves the VaultAccount to receive NFTs
        // When: the user calls safeTransferFrom() to VaultAccount
        // Then: custody[user][nftAddress] increments by 1
        // And: DepositRecorded emitted from VaultAccount
        // And: VaultRoot.recordDeposit() is called
    }

    function test_vaultAccount_nftBlessEscrow_movesFromProtocolEscrow() public {
        // Given: VaultAccount has 2 NFTs held in its own custody
        // When: backend calls blessEscrow(user, nftAddress, 1)
        // Then: user's custody[user][nftAddress].escrow += 1
        // And: custody[address(this)][nftAddress].escrow -= 1
    }

    function test_vaultAccount_nftWithdrawTo_transfersNFT() public {
        // Given: user has 1 escrowed NFT
        // When: backend calls withdrawTo(user, nftAddress, 1, 0, ...)
        // Then: NFT is sent from VaultAccount to user
        // And: VaultRoot.recordWithdrawal is called
    }

    function test_vaultAccount_nftWithdraw_userOwned_returnsNFT() public {
        // Given: user owns 1 NFT in VaultAccount (userOwned)
        // When: user calls withdraw()
        // Then: NFT is returned to user
        // And: VaultRoot.recordWithdrawal() is called
    }

    function test_vaultAccount_globalUnlock_withdrawsEscrowedNFT() public {
        // Given: VaultRoot.refund() returns true
        // And: user has escrowed NFT
        // When: user calls withdraw()
        // Then: escrowed NFT is returned to user
        // And: custody[escrow] reduced
    }

} 