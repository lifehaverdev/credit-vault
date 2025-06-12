// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {VaultRoot} from "../src/VaultRoot.sol";
import {VaultAccount} from "../src/VaultAccount.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";

contract VaultTest is Test {
    VaultRoot root;

    address admin;
    address backend;
    address user;
    address anotherUser;
    
    // Using a real ERC20 for more realistic fork testing
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address internal pepeWhale = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    function setUp() public {
        admin = makeAddr("admin");
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
} 