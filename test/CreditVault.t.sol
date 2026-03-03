// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CreditVault} from "src/CreditVault.sol";
import {TestToken} from "test/mocks/TestToken.sol";
import {MockERC721} from "test/mocks/MockERC721.sol";
import {ReentrancyAttackerV2} from "test/mocks/ReentrancyAttackerV2.sol";

contract CreditVaultTest is Test {
    CreditVault vault;
    address owner = address(0xA11CE);
    address alice = address(0xA11CE1);
    address bob   = address(0xB0B);

    TestToken token;
    MockERC721 nft;

    function setUp() public {
        CreditVault impl = new CreditVault();
        // Deploy as plain contract for unit tests (no proxy needed)
        vault = impl;
        vault.initialize(owner);

        token = new TestToken();
        token.transfer(alice, 1000e18);
        token.transfer(bob, 1000e18);

        nft = new MockERC721();
        nft.mint(alice, 1);
        nft.mint(alice, 2);
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

        vm.expectEmit(true, true, true, true);
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
        vm.expectEmit(true, true, true, true);
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
    // Reentrancy
    // =========================================================================

    function test_payETH_reentrancy_reverts() public {
        // Register attacker as referral address
        bytes32 key = keccak256("attacker");
        address attacker = address(new ReentrancyAttackerV2(address(vault), key));

        vm.prank(attacker);
        vault.register("attacker");
        vm.prank(attacker);
        vault.setAddress(key, attacker);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        // Should revert because attacker tries to re-enter during referral push
        vm.expectRevert();
        vault.payETH{value: 1 ether}(key);
    }

    // =========================================================================
    // Multicall
    // =========================================================================

    function test_multicall_batchesPayments() public {
        vm.startPrank(alice);
        token.approve(address(vault), 200e18);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(vault.pay, (address(token), 100e18, bytes32(0)));
        calls[1] = abi.encodeCall(vault.pay, (address(token), 100e18, bytes32(0)));

        vault.multicall(calls);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), 200e18);
    }
}
