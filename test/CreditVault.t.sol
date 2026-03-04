// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CreditVault} from "src/CreditVault.sol";
import {TestToken} from "test/mocks/TestToken.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {ReentrancyAttackerV2} from "test/mocks/ReentrancyAttackerV2.sol";
import {MockERC1155} from "test/mocks/MockERC1155.sol";
import {LibClone} from "solady/utils/LibClone.sol";

contract CreditVaultTest is Test {
    CreditVault vault;
    address owner = address(0xA11CE);
    address alice = address(0xA11CE1);
    address bob   = address(0xB0B);

    TestToken token;
    MockERC721 nft;
    MockERC1155 erc1155;

    function setUp() public {
        CreditVault impl = new CreditVault();
        // Deploy through an ERC1967 proxy so _disableInitializers() on the impl is respected.
        address proxy = LibClone.deployERC1967(address(impl));
        vault = CreditVault(payable(proxy));
        vault.initialize(owner);

        token = new TestToken();
        token.transfer(alice, 1000e18);
        token.transfer(bob, 1000e18);

        nft = new MockERC721();
        nft.mint(alice, 1);
        nft.mint(alice, 2);

        erc1155 = new MockERC1155();
        erc1155.mint(alice, 1, 10);
    }

    // =========================================================================
    // register
    // =========================================================================

    function test_register_claimsName() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");
        assertEq(vault.referralOwner(key), alice);
        assertEq(vault.referralAddress(key), alice);
    }

    function test_register_emitsEvent() public {
        bytes32 key = keccak256("alice");
        vm.expectEmit(true, false, false, true);
        emit CreditVault.ReferralRegistered(key, "alice", alice);
        vm.prank(alice);
        vault.register("alice");
    }

    function test_register_revertsIfTaken() public {
        vm.prank(alice);
        vault.register("alice");
        vm.prank(bob);
        vm.expectRevert(CreditVault.AlreadyRegistered.selector);
        vault.register("alice");
    }

    // =========================================================================
    // setAddress
    // =========================================================================

    function test_setAddress_updatesPayoutAddress() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");

        vm.prank(alice);
        vault.setAddress(key, bob);
        assertEq(vault.referralAddress(key), bob);
    }

    function test_setAddress_revertsIfNotOwner() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");

        vm.prank(bob);
        vm.expectRevert(CreditVault.NotReferralOwner.selector);
        vault.setAddress(key, bob);
    }

    // =========================================================================
    // transferName
    // =========================================================================

    function test_transferName_changesOwner() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");

        vm.prank(alice);
        vault.transferName(key, bob);
        assertEq(vault.referralOwner(key), bob);
    }

    function test_transferName_revertsIfNotOwner() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");

        vm.prank(bob);
        vm.expectRevert(CreditVault.NotReferralOwner.selector);
        vault.transferName(key, bob);
    }

    function test_transferName_revertsIfZeroAddress() public {
        vm.prank(alice);
        vault.register("alice");
        bytes32 key = keccak256("alice");

        vm.prank(alice);
        vm.expectRevert(CreditVault.ZeroAddress.selector);
        vault.transferName(key, address(0));
    }

    // =========================================================================
    // pay (ERC20, no referral)
    // =========================================================================

    function test_pay_noReferral_accumulatesProtocol() public {
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.pay(address(token), 100e18, bytes32(0));
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), 100e18);
    }

    function test_pay_noReferral_emitsPayment() public {
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);

        vm.expectEmit(true, true, false, true);
        emit CreditVault.Payment(alice, bytes32(0), address(token), 100e18, 100e18, 0);
        vault.pay(address(token), 100e18, bytes32(0));
        vm.stopPrank();
    }

    // =========================================================================
    // pay (ERC20, with referral)
    // =========================================================================

    function test_pay_withReferral_splitsPushesToReferrer() public {
        // bob registers a referral name
        vm.prank(bob);
        vault.register("bob");
        bytes32 key = keccak256("bob");

        // alice pays with bob's referral key
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.pay(address(token), 100e18, key);
        vm.stopPrank();

        // bob gets 5% = 5e18 pushed immediately
        assertEq(token.balanceOf(bob), 1000e18 + 5e18);
        // vault holds 95e18 for protocol
        assertEq(token.balanceOf(address(vault)), 95e18);
    }

    function test_pay_withReferral_emitsCorrectAmounts() public {
        vm.prank(bob);
        vault.register("bob");
        bytes32 key = keccak256("bob");

        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vm.expectEmit(true, true, false, true);
        emit CreditVault.Payment(alice, key, address(token), 100e18, 95e18, 5e18);
        vault.pay(address(token), 100e18, key);
        vm.stopPrank();
    }

    function test_pay_withCustomBps_usesCustomRate() public {
        vm.prank(bob);
        vault.register("bob");
        bytes32 key = keccak256("bob");

        // admin sets bob's rate to 10%
        vm.prank(owner);
        vault.setReferralBps(key, 1000);

        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.pay(address(token), 100e18, key);
        vm.stopPrank();

        assertEq(token.balanceOf(bob), 1000e18 + 10e18);
        assertEq(token.balanceOf(address(vault)), 90e18);
    }

    function test_pay_zeroAmount_reverts() public {
        vm.startPrank(alice);
        token.approve(address(vault), 0);
        vm.expectRevert(CreditVault.ZeroAmount.selector);
        vault.pay(address(token), 0, bytes32(0));
        vm.stopPrank();
    }

    // =========================================================================
    // payETH
    // =========================================================================

    function test_payETH_noReferral_accumulatesProtocol() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.payETH{value: 1 ether}(bytes32(0));
        assertEq(address(vault).balance, 1 ether);
    }

    function test_payETH_withReferral_pushesToReferrer() public {
        vm.prank(bob);
        vault.register("bob");
        bytes32 key = keccak256("bob");

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.payETH{value: 1 ether}(key);

        // bob gets 5% = 0.05 ether
        assertEq(bob.balance, 0.05 ether);
        // vault holds 0.95 ether
        assertEq(address(vault).balance, 0.95 ether);
    }

    function test_receive_noReferral_accumulatesProtocol() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(vault).balance, 1 ether);
    }

    // =========================================================================
    // setDefaultBps
    // =========================================================================

    function test_setDefaultBps_updatesDefault() public {
        vm.prank(owner);
        vault.setDefaultBps(1000);
        assertEq(vault.defaultReferralBps(), 1000);
    }

    function test_setDefaultBps_revertsIfExceedsCap() public {
        vm.prank(owner);
        vm.expectRevert(CreditVault.BpsExceedsCap.selector);
        vault.setDefaultBps(5001);
    }

    function test_setDefaultBps_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setDefaultBps(1000);
    }

    // =========================================================================
    // setReferralBps
    // =========================================================================

    function test_setReferralBps_revertsIfExceedsCap() public {
        vm.prank(bob);
        vault.register("bob");
        bytes32 key = keccak256("bob");

        vm.prank(owner);
        vm.expectRevert(CreditVault.BpsExceedsCap.selector);
        vault.setReferralBps(key, 5001);
    }

    // =========================================================================
    // withdrawProtocol
    // =========================================================================

    function test_withdrawProtocol_ETH() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.payETH{value: 1 ether}(bytes32(0));

        address treasury = address(0xCAFE);
        vm.prank(owner);
        vault.withdrawProtocol(address(0), treasury, 1 ether);
        assertEq(treasury.balance, 1 ether);
        assertEq(address(vault).balance, 0);
    }

    function test_withdrawProtocol_ERC20() public {
        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.pay(address(token), 100e18, bytes32(0));
        vm.stopPrank();

        address treasury = address(0xCAFE);
        vm.prank(owner);
        vault.withdrawProtocol(address(token), treasury, 100e18);
        assertEq(token.balanceOf(treasury), 100e18);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_withdrawProtocol_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawProtocol(address(0), alice, 1 ether);
    }

    // =========================================================================
    // NFT receiving
    // =========================================================================

    function test_onERC721Received_acceptsNFT() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), 1);
        assertEq(nft.ownerOf(1), address(vault));
    }

    function test_onERC721Received_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit CreditVault.NFTReceived(alice, address(nft), 1);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), 1);
    }

    // =========================================================================
    // withdrawNFT
    // =========================================================================

    function test_withdrawNFT_transfersToRecipient() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), 1);

        vm.prank(owner);
        vault.withdrawNFT(address(nft), 1, bob);
        assertEq(nft.ownerOf(1), bob);
    }

    function test_withdrawNFT_revertsIfNotOwner() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(vault), 1);

        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawNFT(address(nft), 1, alice);
    }

    // =========================================================================
    // ERC1155 receiving and withdrawal
    // =========================================================================

    function test_onERC1155Received_acceptsToken() public {
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(vault), 1, 5, "");
        // vault holds 5 of token id 1
    }

    function test_onERC1155Received_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit CreditVault.ERC1155TokenReceived(alice, address(erc1155), 1, 5);
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(vault), 1, 5, "");
    }

    function test_withdrawERC1155_transfersToRecipient() public {
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(vault), 1, 5, "");

        vm.prank(owner);
        vault.withdrawERC1155(address(erc1155), 1, 5, bob);
        // bob now has 5 of token id 1 — verify via balanceOf
        assertEq(erc1155.balanceOf(bob, 1), 5);
    }

    function test_withdrawERC1155_revertsIfNotOwner() public {
        vm.prank(alice);
        erc1155.safeTransferFrom(alice, address(vault), 1, 5, "");

        vm.prank(alice);
        vm.expectRevert();
        vault.withdrawERC1155(address(erc1155), 1, 5, alice);
    }

    function test_onERC1155BatchReceived_acceptsAndEmits() public {
        erc1155.mint(alice, 2, 20);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 1; ids[1] = 2;
        amounts[0] = 5; amounts[1] = 10;

        vm.expectEmit(true, true, false, true);
        emit CreditVault.ERC1155TokenReceived(alice, address(erc1155), 1, 5);
        vm.expectEmit(true, true, false, true);
        emit CreditVault.ERC1155TokenReceived(alice, address(erc1155), 2, 10);

        vm.prank(alice);
        erc1155.safeBatchTransferFrom(alice, address(vault), ids, amounts, "");

        assertEq(erc1155.balanceOf(address(vault), 1), 5);
        assertEq(erc1155.balanceOf(address(vault), 2), 10);
    }

    // =========================================================================
    // Reentrancy
    // =========================================================================

    function test_payETH_revertingReferrer_skipscut() public {
        // Deploy a contract with no receive() — it will revert on ETH push
        address nonPayable = address(new NonPayableContract());

        vm.prank(nonPayable);
        vault.register("broken");
        bytes32 key = keccak256("broken");

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        // Payment should succeed — referral cut skipped, protocol keeps full amount
        vault.payETH{value: 1 ether}(key);

        assertEq(address(vault).balance, 1 ether);
        assertEq(nonPayable.balance, 0);
    }

    function test_payETH_reentrancy_cutSkipped() public {
        // Reentrant referral recipient: its receive() tries to re-enter payETH.
        // The reentrancy guard fires inside the push, the push fails silently,
        // the cut is skipped, and the payment succeeds — attacker gets nothing.
        bytes32 key = keccak256("attacker");
        address attacker = address(new ReentrancyAttackerV2(address(vault), key));

        vm.prank(attacker);
        vault.register("attacker");
        vm.prank(attacker);
        vault.setAddress(key, attacker);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vault.payETH{value: 1 ether}(key);

        // Payment succeeds, attacker gets no cut, vault holds full amount
        assertEq(address(vault).balance, 1 ether);
        assertEq(attacker.balance, 0);
    }

    // =========================================================================
    // Multicall
    // =========================================================================

    function test_multicall_onlyOwner() public {
        // Fund vault with ETH and ERC20
        vm.deal(alice, 2 ether);
        vm.prank(alice);
        vault.payETH{value: 2 ether}(bytes32(0));

        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vault.pay(address(token), 100e18, bytes32(0));
        vm.stopPrank();

        // Non-owner cannot multicall
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(vault.withdrawProtocol, (address(token), alice, 100e18));
        vm.prank(alice);
        vm.expectRevert();
        vault.multicall(calls);

        // Owner can batch withdrawals
        calls = new bytes[](2);
        calls[0] = abi.encodeCall(vault.withdrawProtocol, (address(0), owner, 2 ether));
        calls[1] = abi.encodeCall(vault.withdrawProtocol, (address(token), owner, 100e18));

        vm.prank(owner);
        vault.multicall(calls);

        assertEq(address(vault).balance, 0);
        assertEq(token.balanceOf(owner), 100e18);
    }
}

/// @dev Helper: a contract with no receive() — reverts on ETH push
contract NonPayableContract {}
