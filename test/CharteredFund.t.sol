// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {CharteredFundImplementationV2} from "./mocks/CharteredFundImplementationV2.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

contract CharteredFundTest is Test {
    // Core contracts
    Foundation root;
    CharteredFundImplementation fund;

    // Actors
    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address fundOwner;
    address user;

    // Real PEPE token + whale for fork realism
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address private constant PEPE_WHALE = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    // Owner-NFT for governance
    address ownerNFT;
    uint256 ownerTokenId;

    // Events copied from Foundation
    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event ContributionRescinded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);

    /*//////////////////////////////////////////////////////////////////////////
                                    SETUP
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public {
        uint256 fork = vm.createSelectFork(vm.rpcUrl("mainnet"));

        backend = makeAddr("backend");
        fundOwner = makeAddr("fundOwner");
        user = makeAddr("user");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(fundOwner, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(PEPE_WHALE, 10 ether);

        // ─── Deploy beacon and root ──────────────────────────────────────────
        address cfImpl = address(new CharteredFundImplementation());
        address beacon = address(new UpgradeableBeacon(admin, cfImpl));

        (ownerNFT, ownerTokenId) = _selectOwnerNFT();

        address proxy = new ERC1967Factory().deploy(address(new Foundation()), admin);
        root = Foundation(payable(proxy));
        vm.prank(admin);
        root.initialize(ownerNFT, ownerTokenId, beacon);

        // Transfer beacon ownership to root so upgrades work in future
        vm.prank(admin);
        UpgradeableBeacon(beacon).transferOwnership(address(root));

        // Authorize backend marshal
        vm.prank(admin);
        root.setMarshal(backend, true);

        // ─── Charter single fund for tests ───────────────────────────────────
        bytes32 salt = bytes32(uint256(0xDEADBEEF));
        vm.prank(backend);
        address fundAddress = root.charterFund(fundOwner, salt);
        fund = CharteredFundImplementation(payable(fundAddress));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   HELPERS
    //////////////////////////////////////////////////////////////////////////*/
    function _getCustodyKey(address _user, address _token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _token));
    }

    function _splitAmount(bytes32 amount) internal pure returns (uint128 userOwned, uint128 escrow) {
        userOwned = uint128(uint256(amount));
        escrow = uint128(uint256(amount >> 128));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Backend sponsors a user inside the fund.
    function test_contributeFor_byBackend() public {
        uint256 amount = 1_000_000 * 1e18;

        // Move PEPE from whale to backend for realism
        vm.prank(PEPE_WHALE);
        ERC20(PEPE).transfer(backend, amount);

        // Approve and contributeFor
        vm.prank(admin);
        root.setFreeze(false); // ensure backend ops allowed

        vm.startPrank(backend);
        ERC20(PEPE).approve(address(fund), amount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(fund), user, PEPE, amount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(fund), user, PEPE, amount);
        fund.contributeFor(user, PEPE, amount);
        vm.stopPrank();

        // Assert custody
        bytes32 k = _getCustodyKey(user, PEPE);
        (uint128 owned, uint128 esc) = _splitAmount(fund.custody(k));
        assertEq(owned, amount);
        assertEq(esc, 0);
    }

    /// @notice Backend converts userOwned to escrow via commit.
    function test_commit_movesBalance() public {
        uint256 amount = 50_000 * 1e18;

        // User contributes
        vm.startPrank(PEPE_WHALE);
        ERC20(PEPE).approve(address(fund), amount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(fund), PEPE_WHALE, PEPE, amount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(fund), PEPE_WHALE, PEPE, amount);
        fund.contribute(PEPE, amount);
        vm.stopPrank();

        // custody before
        bytes32 k = _getCustodyKey(PEPE_WHALE, PEPE);
        (uint128 beforeOwned, uint128 beforeEsc) = _splitAmount(fund.custody(k));
        assertEq(beforeOwned, amount);
        assertEq(beforeEsc, 0);

        // backend commit half
        uint256 escrowAmt = amount / 2;
        vm.prank(admin);
        root.setFreeze(false);

        vm.startPrank(backend);
        // No strict event expectations; focus on state change
        fund.commit(address(fund), PEPE_WHALE, PEPE, escrowAmt, 0, 0, "");
        vm.stopPrank();

        (uint128 afterOwned, uint128 afterEsc) = _splitAmount(fund.custody(k));
        assertEq(afterOwned, beforeOwned - escrowAmt);
        assertEq(afterEsc, escrowAmt);
    }

    /// @notice User rescinds their userOwned funds from the fund.
    function test_requestRescission_userOwned() public {
        uint256 amount = 2 ether;
        vm.prank(fundOwner);
        (bool ok,) = address(fund).call{value: amount}("");
        require(ok);

        uint256 balBefore = fundOwner.balance;

        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(fund), fundOwner, address(0), amount);
        vm.prank(fundOwner);
        fund.requestRescission(address(0));

        uint256 balAfter = fundOwner.balance;
        assertTrue(balAfter > balBefore);

        bytes32 k = _getCustodyKey(fundOwner, address(0));
        (uint128 owned,) = _splitAmount(fund.custody(k));
        assertEq(owned, 0);
    }

    /// @notice Backend remits escrowed PEPE from fund to user with fee.
    function test_remit_byBackend() public {
        uint256 amount = 1000 * 1e18;
        vm.startPrank(PEPE_WHALE);
        ERC20(PEPE).approve(address(fund), amount);
        fund.contribute(PEPE, amount);
        vm.stopPrank();

        // move all to escrow
        vm.prank(backend);
        fund.commit(address(fund), PEPE_WHALE, PEPE, amount, 0, 0, "seed");

        uint128 fee = 10 * 1e18;
        uint256 remitAmount = amount / 2;

        uint256 userBalBefore = ERC20(PEPE).balanceOf(PEPE_WHALE);

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit RemittanceProcessed(address(fund), PEPE_WHALE, PEPE, remitAmount, fee, "remit");
        fund.remit(PEPE_WHALE, PEPE, remitAmount, fee, "remit");
        vm.stopPrank();

        uint256 userBalAfter = ERC20(PEPE).balanceOf(PEPE_WHALE);
        assertEq(userBalAfter, userBalBefore + remitAmount);

        bytes32 k = _getCustodyKey(PEPE_WHALE, PEPE);
        (, uint128 esc) = _splitAmount(fund.custody(k));
        assertEq(esc, amount - remitAmount - fee);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NFT test helpers
    //////////////////////////////////////////////////////////////////////////*/
    function _selectOwnerNFT() internal returns (address nft, uint256 tokenId) {
        address milady = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
        uint256 id = 598;
        (bool ok, bytes memory data) = milady.staticcall(abi.encodeWithSelector(0x6352211e, id));
        if (ok && data.length == 32 && abi.decode(data, (address)) == admin) {
            return (milady, id);
        }
        MockERC721 mock = new MockERC721();
        mock.mint(admin, 1);
        return (address(mock), 1);
    }
}
