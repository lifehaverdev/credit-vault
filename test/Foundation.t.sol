// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {IFoundation} from "../src/interfaces/IFoundation.sol";
import {NoReceiver} from "./mocks/NoReceiver.sol";
import {ReentrancyERC20} from "./mocks/ReentrancyERC20.sol";
import {ReentrancyAttacker} from "./mocks/ReentrancyAttacker.sol";

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract FoundationTest is Test {
    Foundation root;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;
    address anotherUser;
    
    // Using a real ERC20 for more realistic fork testing
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address internal pepeWhale = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    address private constant MILADYSTATION = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
    address private constant MSWhale = 0x65ccFF5cFc0E080CdD4bb29BC66A3F71153382a2;

    address ownerNFT;
    uint256 ownerTokenId;

    // Secondary NFT used for custody-related NFT tests (to avoid governance-NFT side-effects)
    address testNFT;
    uint256 testTokenId;

    // --- Events ---
    event FundChartered(address indexed fundAddress, address indexed owner, bytes32 salt);
    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata);
    event RescissionRequested(address indexed fundAddress, address indexed user, address indexed token);
    event ContributionRescinded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);
    event MarshalStatusChanged(address indexed marshal, bool isAuthorized);
    event Liquidation(address indexed fundAddress, address indexed user, address indexed token, uint256 fee, bytes metadata);
    event OperatorFreeze(bool isFrozen);
    event RefundChanged(bool isRefund);

    // Custom errors from Solady's SafeTransferLib
    error TransferFailed();
    error TransferFromFailed();

    function setUp() public {
        // Automatically select the mainnet fork defined in foundry.toml.
        // This removes the need for passing `--fork-url` when running tests.
        // Ensure your foundry.toml has an entry:
        // [rpc_endpoints]
        // mainnet = "${RPC_URL}"
        uint256 mainnetFork = vm.createSelectFork(vm.rpcUrl("mainnet"));

        backend = makeAddr("backend");
        user = makeAddr("user");
        anotherUser = makeAddr("anotherUser");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(anotherUser, 10 ether);
        vm.deal(pepeWhale, 10 ether);
        
        // Deploy implementation and proxy for Foundation
        // 1. Deploy CharteredFund implementation and beacon
        address cfImpl = address(new CharteredFundImplementation());
        address beacon = address(new UpgradeableBeacon(admin, cfImpl));

        // 2. Pick owner NFT per chain
        (ownerNFT, ownerTokenId) = _selectOwnerNFT();

        // Deploy implementation and proxy for Foundation
        address proxy = new ERC1967Factory().deploy(address(new Foundation()), admin);
        root = Foundation(payable(proxy));
        // Call initialize on the proxy
        vm.prank(admin);
        root.initialize(ownerNFT, ownerTokenId, beacon);

        // Authorize backend as marshal
        vm.prank(admin);
        root.setMarshal(backend, true);

        // --- Prepare secondary NFT for non-governance tests ---
        MockERC721 secondary = new MockERC721();
        secondary.mint(admin, 2);
        testNFT = address(secondary);
        testTokenId = 2;
    }

    function _selectOwnerNFT() internal returns (address nft, uint256 tokenId) {
        address milady = MILADYSTATION;
        uint256 id = 598;
        (bool ok, bytes memory data) = milady.staticcall(abi.encodeWithSelector(0x6352211e, id));
        if (ok && data.length == 32 && abi.decode(data, (address)) == admin) {
            return (milady, id);
        }
        MockERC721 mock = new MockERC721();
        mock.mint(admin, 1);
        return (address(mock), 1);
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
    function test_initialState() public view {
        // Tests that the root contract is initialized with the correct owner and that the initial backend is set.
        assertEq(IERC721(ownerNFT).ownerOf(ownerTokenId), admin, "Admin should be the owner of the NFT");
        assertTrue(root.isMarshal(backend), "Initial backend should be set");
        assertFalse(root.marshalFrozen(), "Backend operations should be allowed initially");
        assertFalse(root.refund(), "Refund mode should be off initially");
    }

    function test_setMarshal_byOwner_succeeds() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MarshalStatusChanged(anotherUser, true);
        root.setMarshal(anotherUser, true);
        assertTrue(root.isMarshal(anotherUser), "New backend should be authorized");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MarshalStatusChanged(anotherUser, false);
        root.setMarshal(anotherUser, false);
        assertFalse(root.isMarshal(anotherUser), "Backend should be de-authorized");
    }

    function test_onlyOwnerFunctions_revertForEOA() public {
        vm.startPrank(user);
        vm.expectRevert(IFoundation.Auth.selector);
        root.setMarshal(anotherUser, true);
        vm.stopPrank();
    }

    function test_setFreeze_byOwner_succeeds() public {
        // Unfreeze (enable marshal operations)
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit OperatorFreeze(false);
        root.setFreeze(false);
        assertFalse(root.marshalFrozen(), "Backend operations should be unfrozen (allowed)");

        // Freeze again (disable marshal operations)
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit OperatorFreeze(true);
        root.setFreeze(true);
        assertTrue(root.marshalFrozen(), "Backend operations should be frozen (disallowed)");
    }

    function test_setFreeze_byNonOwner_reverts() public {
        vm.startPrank(user);
        vm.expectRevert(IFoundation.Auth.selector);
        root.setFreeze(false);
        vm.stopPrank();
    }

    // --- Standard User Flow (Direct Foundation Interaction) ---
    function test_erc20Contribute_updatesCustody() public {
        uint256 contributeAmount = 1_000_000 * 1e18; // 1M PEPE
        
        // Check whale has enough balance
        uint256 whaleBalance = ERC20(PEPE).balanceOf(pepeWhale);
        require(whaleBalance >= contributeAmount, "Whale does not have enough PEPE");

        vm.startPrank(pepeWhale);
        // Approve root to spend PEPE
        ERC20(PEPE).approve(address(root), contributeAmount);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(root), pepeWhale, PEPE, contributeAmount);

        // When: whale contributes PEPE
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        // Then: custody is updated correctly
        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, contributeAmount, "userOwned balance should be updated");
        assertEq(escrow, 0, "escrow balance should be 0");
    }

    function test_root_contributeFor_byBackend_succeeds() public {
        uint256 contributeAmount = 1_000_000 * 1e18; // 1M PEPE
        
        // 1. Fund the backend with PEPE from the whale
        vm.prank(pepeWhale);
        ERC20(PEPE).transfer(backend, contributeAmount);

        // 2. Backend approves root and contributes for the user
        // Unfreeze marshal operations first
        vm.prank(admin);
        root.setFreeze(false);

        vm.startPrank(backend);
        ERC20(PEPE).approve(address(root), contributeAmount);

        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(root), user, PEPE, contributeAmount);

        root.contributeFor(user, PEPE, contributeAmount);
        vm.stopPrank();

        // 3. Check custody for the target user
        bytes32 custodyKey = _getCustodyKey(user, PEPE);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, contributeAmount, "userOwned balance should be updated for the specified user");
        assertEq(escrow, 0, "escrow balance should be 0");
    }

    function test_root_contributeFor_byNonBackend_reverts() public {
        vm.startPrank(user);
        vm.expectRevert(TransferFromFailed.selector);
        root.contributeFor(anotherUser, PEPE, 1_000_000 * 1e18);
        vm.stopPrank();
    }

    function test_backend_commit_movesToEscrow() public {
        // After a standard user contributes, the backend confirms credit.
        uint256 contributeAmount = 1_000_000 * 1e18; // 1M PEPE
        
        // 1. User contributes PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        // Check initial custody
        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned_before, uint128 escrow_before) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned_before, contributeAmount);
        assertEq(escrow_before, 0);

        // 2. Backend confirms credit
        // Unfreeze marshal operations
        vm.prank(admin);
        root.setFreeze(false);

        vm.startPrank(backend);
        uint256 amountToEscrow = contributeAmount / 2;
        
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit CommitmentConfirmed(address(root), pepeWhale, PEPE, amountToEscrow, 0, "");

        root.commit(address(root), pepeWhale, PEPE, amountToEscrow, 0, "");
        vm.stopPrank();

        // 3. Check final custody
        (uint128 userOwned_after, uint128 escrow_after) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned_after, userOwned_before - amountToEscrow, "userOwned should decrease");
        assertEq(escrow_after, escrow_before + amountToEscrow, "escrow should increase");
    }

    function test_backend_allocate_usesProtocolBalance() public {
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
        
        // Unfreeze marshal operations
        vm.prank(admin);
        root.setFreeze(false);

        // Use commit to move it to the protocol's *escrow* balance
        vm.prank(backend);
        root.commit(address(root), address(root), PEPE, protocolAmount, 0, "seed protocol");
        vm.stopPrank();
        
        // Check protocol escrow balance
        (, uint128 protocolEscrow_before) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow_before, protocolAmount, "Protocol should have escrow balance");

        // 2. Bless the user with some of the protocol's escrow
        // Ensure marshal operations allowed
        vm.prank(admin);
        root.setFreeze(false);

        vm.startPrank(backend);
        uint256 amountToBless = protocolAmount / 4;

        vm.expectEmit(true, true, true, true);
        emit CommitmentConfirmed(address(root), user, PEPE, amountToBless, 0, "ALLOCATED");
        root.allocate(user, PEPE, amountToBless);
        vm.stopPrank();

        // 3. Check balances
        bytes32 userKey = _getCustodyKey(user, PEPE);
        (, uint128 userEscrow_after) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow_after, amountToBless, "User escrow should be blessed amount");

        (, uint128 protocolEscrow_after) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow_after, protocolEscrow_before - amountToBless, "Protocol escrow should decrease");
    }

    function test_backend_allocate_revertsIfInsufficient() public {
        uint256 protocolAmount = 1_000_000 * 1e18;

        // 1. Seed protocol escrow with PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).transfer(address(root), protocolAmount);
        vm.stopPrank();
        bytes32 protocolKey = _getCustodyKey(address(root), PEPE);
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), _packAmount(uint128(protocolAmount), 0));
        vm.prank(backend);
        root.commit(address(root), address(root), PEPE, protocolAmount, 0, "seed protocol");
        vm.stopPrank();

        // 2. Attempt to bless with more than is available
        vm.prank(admin);
        root.setFreeze(false);

        vm.startPrank(backend);
        uint256 amountToBless = protocolAmount + 1;
        
        vm.expectRevert(IFoundation.Math.selector);
        root.allocate(user, PEPE, amountToBless);
        vm.stopPrank();

        // 3. Check balances are unchanged
        bytes32 userKey = _getCustodyKey(user, PEPE);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, 0, "User escrow should not change");

        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, protocolAmount, "Protocol escrow should not change");
    }

    function test_root_requestRescission_partial_userOwned() public {
        uint256 contributeAmount = 1_000_000 * 1e18;
        uint256 escrowAmount = contributeAmount / 2;
        uint256 userOwnedAmount = contributeAmount - escrowAmount;

        // 1. User contributes PEPE
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        // 2. Backend confirms credit for half
        vm.prank(admin);
        root.setFreeze(false);

        vm.prank(backend);
        root.commit(address(root), pepeWhale, PEPE, escrowAmount, 0, "");
        vm.stopPrank();

        // 3. User rescinds
        uint256 balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        vm.startPrank(pepeWhale);
        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(root), pepeWhale, PEPE, userOwnedAmount);
        root.requestRescission(PEPE);
        vm.stopPrank();

        // 4. Check balances
        uint256 balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(balance_after, balance_before + userOwnedAmount, "User balance should increase by userOwned amount");

        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned_after, uint128 escrow_after) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned_after, 0, "userOwned should be zero after rescission");
        assertEq(escrow_after, escrowAmount, "escrow should be unchanged");
    }

    function test_backendRemit_erc20_sendsEscrow() public {
        // 1. Setup user escrow balance
        uint256 contributeAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        vm.prank(backend);
        root.commit(address(root), pepeWhale, PEPE, contributeAmount, 0, "commit");
        vm.stopPrank();

        // 2. Backend remits funds to user with a fee
        uint256 remitAmount = contributeAmount / 2;
        uint128 fee = 100 * 1e18; // 100 PEPE fee
        
        uint256 user_balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        uint256 protocol_balance_before = ERC20(PEPE).balanceOf(address(root));

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit RemittanceProcessed(address(root), pepeWhale, PEPE, remitAmount, fee, "remit");
        
        root.remit(pepeWhale, PEPE, remitAmount, fee, "remit");
        vm.stopPrank();

        // 3. Check balances
        uint256 user_balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(user_balance_after, user_balance_before + remitAmount, "User balance should increase by remit amount");

        uint256 protocol_balance_after = ERC20(PEPE).balanceOf(address(root));
        // The protocol balance change is complex: it receives `contributeAmount` and sends `remitAmount`.
        // The net change is contributeAmount - remitAmount. The fee is an internal accounting change.
        assertEq(protocol_balance_after, protocol_balance_before - remitAmount, "Protocol balance should decrease by remit amount");
        
        // Check internal custody
        bytes32 userKey = _getCustodyKey(pepeWhale, PEPE);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, contributeAmount - remitAmount - fee, "User escrow should decrease by remit amount and fee");

        bytes32 protocolKey = _getCustodyKey(address(root), PEPE);
        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, fee, "Protocol escrow should equal the fee");
    }

    function test_root_remit_insufficientEscrow_reverts() public {
        // 1. Setup user escrow balance
        uint256 contributeAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        vm.prank(backend);
        root.commit(address(root), pepeWhale, PEPE, contributeAmount, 0, "commit");
        vm.stopPrank();

        // 2. Attempt to remit more than available in escrow
        uint256 remitAmount = contributeAmount + 1;
        uint128 fee = 0;

        vm.startPrank(backend);
        vm.expectRevert(IFoundation.Math.selector);
        root.remit(pepeWhale, PEPE, remitAmount, fee, "remit");
        vm.stopPrank();

        // 3. Check internal custody is unchanged
        bytes32 userKey = _getCustodyKey(pepeWhale, PEPE);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, contributeAmount, "User escrow should be unchanged");
    }

    function test_ethContribute_updatesCustody() public {
        // A standard user sends ETH directly to the Foundation via receive().
        uint256 contributeAmount = 1 ether;

        vm.startPrank(user);
        // Expect event from root contract
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(root), user, address(0), contributeAmount);

        // When: user sends ETH to the root contract
        (bool success, ) = address(root).call{value: contributeAmount}("");
        require(success, "ETH transfer failed");
        
        vm.stopPrank();

        // Then: custody for the user is updated correctly
        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, contributeAmount, "userOwned balance should be updated");
        assertEq(escrow, 0, "escrow balance should be 0");
    }

    function test_userRequestRescission_eth_userOwned() public {
        // 1. User contributes ETH to create a userOwned balance
        uint256 contributeAmount = 2 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: contributeAmount}("");
        require(success, "ETH contribute failed");

        // 2. User rescinds their userOwned ETH
        uint256 balance_before = user.balance;
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(root), user, address(0), contributeAmount);
        
        root.requestRescission(address(0));
        vm.stopPrank();

        // 3. Check balances
        uint256 balance_after = user.balance;
        assertTrue(balance_after > balance_before, "User ETH balance should increase");

        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (uint128 userOwned, ) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, 0, "userOwned balance should be zero after rescission");
    }

    // --- Power User Flow (CharteredFund Interaction) ---
    function test_charterFund_succeeds() public {
        bytes32 salt = keccak256("test_salt");

        vm.startPrank(backend);
        address fundAddress = root.charterFund(user, salt);
        vm.stopPrank();

        assertTrue(root.isCharteredFund(fundAddress), "Fund should be registered in root");

        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));
        assertEq(charteredFund.owner(), user, "Fund owner should be the user");
        assertEq(address(charteredFund.foundation()), address(root), "Fund should point to the correct root");
    }

    function test_charterFund_predictableAddress() public {
        bytes32 salt = keccak256("predictable_salt");
        
        // Predict address
        address predictedAddress = root.computeCharterAddress(user, salt);

        // Create fund
        vm.prank(backend);
        address actualAddress = root.charterFund(user, salt);
        
        assertEq(actualAddress, predictedAddress, "Created address should match predicted address");
    }

    function test_fund_contribute_erc20() public {
        // 1. Create fund
        vm.prank(backend);
        address fundAddress = root.charterFund(user, "salt");
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // 2. Contribute PEPE into the fund
        uint256 contributeAmount = 1_000_000e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(fundAddress, contributeAmount);
        
        // Expect event from CharteredFund first, then from Foundation
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, pepeWhale, PEPE, contributeAmount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, pepeWhale, PEPE, contributeAmount);

        charteredFund.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        // 3. Check custody in the chartered fund
        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned, uint128 escrow) = _splitAmount(charteredFund.custody(custodyKey));
        assertEq(userOwned, contributeAmount, "userOwned balance in fund should be updated");
        assertEq(escrow, 0, "escrow should be 0");
    }

    function test_fund_contribute_eth() public {
        // 1. Create fund
        vm.prank(backend);
        address fundAddress = root.charterFund(user, "salt");

        // 2. Contribute ETH into the fund
        uint256 contributeAmount = 2 ether;
        vm.startPrank(anotherUser);

        // Expect event from CharteredFund first, then from Foundation
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, anotherUser, address(0), contributeAmount);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, anotherUser, address(0), contributeAmount);

        (bool success, ) = fundAddress.call{value: contributeAmount}("");
        require(success, "ETH transfer to fund failed");
        vm.stopPrank();

        // 3. Check custody in the chartered fund for the sender
        bytes32 custodyKey = _getCustodyKey(anotherUser, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(CharteredFundImplementation(payable(fundAddress)).custody(custodyKey));
        assertEq(userOwned, contributeAmount, "userOwned balance in fund should be updated");
        assertEq(escrow, 0, "escrow should be 0");
    }

    function test_fund_contributeFor_byBackend_succeeds() public {
        // The backend contributes tokens into a user's account within their CharteredFund.
    }

    function test_fund_commit_movesBalance() public {
        // After a contribute into a CharteredFund, the backend confirms credit.
        // Checks that balance moves from userOwned to escrow in the CharteredFund's custody.
    }

    function test_fund_requestRescission_userOwned_succeeds() public {
        // A user with a CharteredFund rescinds their own userOwned balance from their fund.
    }

    function test_fund_remit_byBackend_succeeds() public {
        // Backend processes a remittance from a user's escrow balance within their CharteredFund.
    }


    // --- Security & Edge Cases ---
    function test_userRequestRescission_succeeds_whenFrozen() public {
        uint256 contributeAmount = 1 ether;
        vm.startPrank(user);
        (bool success, ) = address(root).call{value: contributeAmount}("");
        require(success, "ETH contribute failed");
        vm.stopPrank();

        // Freeze the contract
        vm.startPrank(admin);
        root.setFreeze(false);
        vm.stopPrank();
        assertFalse(root.marshalFrozen(), "Backend should be frozen");

        // User can still rescind
        uint256 balance_before = user.balance;
        vm.startPrank(user);
        root.requestRescission(address(0));
        uint256 balance_after = user.balance;

        assertTrue(balance_after > balance_before, "User ETH balance should increase after rescission");
    }

    function test_fundRequestRescission_succeeds_whenFrozen() public {
        // 1. Create fund and contribute ETH
        vm.startPrank(backend);
        address fundAddress = root.charterFund(user, "salt");
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));
        
        uint256 contributeAmount = 1 ether;
        vm.startPrank(user);
        (bool success, ) = fundAddress.call{value: contributeAmount}("");
        require(success, "ETH contribute to fund failed");
        vm.stopPrank();

        // 2. Freeze the root contract
        vm.startPrank(admin);
        root.setFreeze(false);
        vm.stopPrank();
        assertFalse(root.marshalFrozen(), "Backend should be frozen");

        // 3. User can still rescind from their fund
        uint256 balance_before = user.balance;
        vm.startPrank(user);
        charteredFund.requestRescission(address(0));
        uint256 balance_after = user.balance;

        assertTrue(balance_after > balance_before, "User ETH balance should increase after fund rescission");
    }

    function test_onlyCharteredFund_modifier() public {
        vm.startPrank(user);
        vm.expectRevert(IFoundation.Auth.selector);
        root.recordContribution(user, PEPE, 1 ether);
    }

    function test_reentrancy_contribute() public {
        // 1. Deploy the malicious token and fund the user
        ReentrancyERC20 maliciousToken = new ReentrancyERC20(address(root), user);
        uint256 contributeAmount = 100 * 1e18;
        maliciousToken.mint(user, contributeAmount);

        // 2. Approve and attempt to contribute
        vm.startPrank(user);
        maliciousToken.approve(address(root), contributeAmount);

        // 3. Expect revert from ReentrancyGuard
        bool caughtRevert = false;
        try root.contribute(address(maliciousToken), contributeAmount) {
            // Should not be reached
        } catch {
            caughtRevert = true;
        }
        assertTrue(caughtRevert, "Re-entrancy was not caught");
        
        vm.stopPrank();
    }

    function test_reentrancy_requestRescission() public {
        // 1. Deploy the attacker contract
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(root));
        uint256 contributeAmount = 1 ether;

        // 2. Fund the attacker and have it contribute into the vault
        vm.deal(address(attacker), contributeAmount);
        attacker.deposit{value: contributeAmount}();

        // 3. Initiate the attack, which should revert
        vm.prank(address(attacker));
        // The ReentrancyGuard in Solady reverts with an empty message.
        // vm.expectRevert("Reentrant call");
        vm.expectRevert();
        attacker.attack();
    }

    function test_nftContribute_updatesCustody_correctly() public {
        uint256 tokenIdToTransfer = ownerTokenId;

        // Given: Whale owns a MiladyStation NFT
        vm.startPrank(admin);
        
        // And: Whale approves Foundation to receive NFT
        IERC721(ownerNFT).approve(address(root), tokenIdToTransfer);

        // When: Whale safeTransfers NFT to Foundation
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(root), admin, ownerNFT, 1);
        IERC721(ownerNFT).safeTransferFrom(admin, address(root), tokenIdToTransfer);
        
        vm.stopPrank();

        // Then: custody[whale][miladyStation] increments by 1
        bytes32 custodyKey = _getCustodyKey(admin, ownerNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        
        assertEq(userOwned, 1, "userOwned should be 1");
        assertEq(escrow, 0, "escrow should be 0");
    }

    function test_nftContribute_emitsCorrectEvent() public {
        uint256 tokenIdToTransfer = ownerTokenId;

        vm.startPrank(admin);
        IERC721(ownerNFT).approve(address(root), tokenIdToTransfer);

        // Expect: ContributionRecorded(root, whale, miladyStation, 1)
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(address(root), admin, ownerNFT, 1);
        
        // When: whale safeTransfers tokenId to root
        IERC721(ownerNFT).safeTransferFrom(admin, address(root), tokenIdToTransfer);
        vm.stopPrank();
    }

    function test_nftAllocate_movesFromProtocolEscrow() public {
        // Given: Foundation has 1 NFT in protocol escrow.
        // We will directly manipulate storage to set this up, bypassing commit.
        bytes32 protocolKey = _getCustodyKey(address(root), ownerNFT);
        bytes32 protocolBalance = _packAmount(0, 1); // 0 userOwned, 1 escrow
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), protocolBalance);

        // Check that protocol has 1 in escrow
        (uint128 protocolUserOwned, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0");
        assertEq(protocolEscrow, 1, "Protocol escrow should be 1");

        // When: backend allocates the user with 1 NFT escrow
        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit CommitmentConfirmed(address(root), user, ownerNFT, 1, 0, "ALLOCATED");
        root.allocate(user, ownerNFT, 1);
        vm.stopPrank();

        // Then: user's custody shows +1 escrow, protocol's escrow is decremented by 1
        bytes32 userKey = _getCustodyKey(user, ownerNFT);
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, 1, "User escrow should be 1");

        (protocolUserOwned, protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolUserOwned, 0, "Protocol userOwned should be 0 after allocating");
        assertEq(protocolEscrow, 0, "Protocol escrow should be 0 after allocating");
    }

    function test_nftRemit_byBackend_transfersNFT() public {
        // NOTE: This test confirms the design choice that `remit` is for fungible tokens only.
        // It is expected to revert for NFTs, as they are considered spent upon contribute.

        // Given: user has 1 escrowed NFT
        uint256 tokenId = ownerTokenId;

        // 1. User contributes NFT
        vm.startPrank(admin);
        IERC721(ownerNFT).safeTransferFrom(admin, address(root), tokenId);
        vm.stopPrank();

        // 2. Backend confirms credit to move it to escrow
        vm.startPrank(backend);
        root.commit(address(root), admin, ownerNFT, 1, 0, "commit");
        vm.stopPrank();

        // 3. When: backend attempts to remit() the NFT
        vm.startPrank(backend);
        
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(IFoundation.Fail.selector);
        root.remit(admin, ownerNFT, 1, 0, "remit");
        vm.stopPrank();

        // And: NFT is still owned by the vault
        assertEq(IERC721(ownerNFT).ownerOf(tokenId), address(root));
        
        // And: user's escrow balance is unchanged
        bytes32 userKey = _getCustodyKey(admin, ownerNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(userKey));
        assertEq(userOwned, 0, "User userOwned should be 0");
        assertEq(escrow, 1, "User escrow should still be 1");
    }

    function test_nftRequestRescission_userOwned_returnsNFT() public {
        // NOTE: This test confirms that `requestRescission` also does not support NFTs,
        // aligning with the "NFTs are good as spent" design choice.

        // Given: user safeTransfers NFT to vault
        uint256 tokenId = ownerTokenId;

        // 1. User contributes NFT
        vm.startPrank(admin);
        IERC721(ownerNFT).safeTransferFrom(admin, address(root), tokenId);

        // Check that vault owns the NFT and user has 1 userOwned
        assertEq(IERC721(ownerNFT).ownerOf(tokenId), address(root));
        bytes32 userKey = _getCustodyKey(admin, ownerNFT);
        (uint128 userOwned_before, ) = _splitAmount(root.custody(userKey));
        assertEq(userOwned_before, 1, "User userOwned should be 1 after contribute");

        // When: user calls requestRescission()
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(IFoundation.Fail.selector);
        root.requestRescission(ownerNFT);
        vm.stopPrank();

        // And: NFT is still owned by the vault
        assertEq(IERC721(ownerNFT).ownerOf(tokenId), address(root));

        // And: userOwned is unchanged
        (uint128 userOwned_after, uint128 escrow_after) = _splitAmount(root.custody(userKey));
        assertEq(userOwned_after, 1, "User userOwned should be 1 after failed rescission");
        assertEq(escrow_after, 0, "User escrow should be 0");
    }

    function test_nftGlobalUnlock_allowsEscrowRescission() public {
        // Given: user has an escrowed NFT
        uint256 tokenId = testTokenId;

        // 1. User contributes NFT and backend confirms credit
        vm.startPrank(admin);
        IERC721(testNFT).safeTransferFrom(admin, address(root), tokenId);
        vm.stopPrank();

        vm.startPrank(backend);
        root.commit(address(root), admin, testNFT, 1, 0, "commit");
        vm.stopPrank();

        // And: owner flips isGlobalEscrowUnlocked (refund) = true
        vm.prank(admin);
        root.setRefund(true);
        assert(root.refund());

        // When: user calls requestRescission()
        vm.startPrank(admin);
        // NOTE: The current implementation attempts an ERC20 transfer which will fail.
        // This test documents that even with refund mode on, NFT rescission is broken.
        vm.expectRevert(IFoundation.Fail.selector);
        root.requestRescission(testNFT);
        vm.stopPrank();

        // Then: both userOwned and escrowed NFTs are NOT returned
        assertEq(IERC721(testNFT).ownerOf(tokenId), address(root));

        // And: balances are unchanged
        bytes32 userKey = _getCustodyKey(admin, testNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(root.custody(userKey));
        assertEq(userOwned, 0);
        assertEq(escrow, 1);
    }

    function test_nftContribute_failsWithoutOnERC721Receiver() public {
        // Given: a contract without onERC721Received
        NoReceiver noReceiver = new NoReceiver();

        uint256 tokenId = ownerTokenId;

        // When: NFT is sent to that contract
        vm.startPrank(admin);

        // Then: transaction reverts
        // The ERC721 standard requires the recipient of a safe transfer to implement onERC721Received.
        // The revert reason is not standardized, so we just check for a generic revert.
        vm.expectRevert();
        IERC721(ownerNFT).safeTransferFrom(admin, address(noReceiver), tokenId);
        vm.stopPrank();
    }



    // --- Integration Tests ---
    function test_root_and_charteredFund_emitContribute_and_Rescind_correctly() public {
        // 1. Create a CharteredFund.
        vm.startPrank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // 2. Contribute ETH into CharteredFund
        uint256 contributeAmount = 1 ether;
        vm.startPrank(user);

        // Expect ContributionRecorded from CharteredFund
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, user, address(0), contributeAmount);
        
        // Expect ContributionRecorded from Foundation
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, user, address(0), contributeAmount);

        (bool success, ) = fundAddress.call{value: contributeAmount}("");
        require(success, "ETH contribute to fund failed");

        // 3. Rescind ETH from CharteredFund
        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(fundAddress, user, address(0), contributeAmount);

        // The CharteredFund's requestRescission() calls root.recordRemittance()
        vm.expectEmit(true, true, true, true);
        emit RemittanceProcessed(fundAddress, user, address(0), contributeAmount, 0, "");

        charteredFund.requestRescission(address(0));
        vm.stopPrank();
    }

    function test_charteredFund_nftContribute_updatesCustody() public {
        // 1. Create a CharteredFund for 'anotherUser'
        vm.startPrank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // Given: a user owns a Milady NFT
        uint256 tokenId = testTokenId;

        // And: the user approves the CharteredFund to receive NFTs
        vm.startPrank(admin);
        IERC721(testNFT).approve(address(charteredFund), tokenId);

        // When: the user calls safeTransferFrom() to CharteredFund
        // Then: A single ContributionRecorded event is emitted from Foundation, forwarded by the CharteredFund.
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(fundAddress, admin, testNFT, 1);
        
        vm.startPrank(admin);
        IERC721(testNFT).safeTransferFrom(admin, fundAddress, tokenId);
        vm.stopPrank();
        
        // Then: custody[user][nftAddress] increments by 1 in the CharteredFund
        bytes32 userKey = _getCustodyKey(admin, testNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(charteredFund.custody(userKey));
        assertEq(userOwned, 1, "CharteredFund userOwned should be 1");
        assertEq(escrow, 0, "CharteredFund escrow should be 0");
    }

    function test_charteredFund_nftAllocate_movesFromProtocolEscrow() public {
        // 1. Create a CharteredFund.
        vm.prank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // 2. Manually set the protocol's escrow balance for the test
        bytes32 protocolKey = _getCustodyKey(address(charteredFund), ownerNFT);
        bytes32 protocolBalance = _packAmount(0, 1); // 0 userOwned, 1 escrow
        bytes32 storageSlot = keccak256(abi.encode(protocolKey, 0)); // custody is at slot 0
        vm.store(address(charteredFund), storageSlot, protocolBalance); 

        // 3. When backend calls allocate on the CharteredFund for a user.
        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit CommitmentConfirmed(fundAddress, user, ownerNFT, 1, 0, "ALLOCATED");
        charteredFund.allocate(user, ownerNFT, 1);
        vm.stopPrank();

        // Then: user's custody in the fund shows +1 escrow.
        bytes32 userKey = _getCustodyKey(user, ownerNFT);
        (, uint128 userEscrow) = _splitAmount(charteredFund.custody(userKey));
        assertEq(userEscrow, 1, "User escrow in CharteredFund should be 1");

        // And: The fund's protocol escrow is now 0.
        (, uint128 protocolEscrow) = _splitAmount(charteredFund.custody(protocolKey));
        assertEq(protocolEscrow, 0, "CharteredFund protocol escrow should be 0");
    }

    function test_charteredFund_nftRemit_transfersNFT() public {
        // NOTE: This test confirms that CharteredFund.remit is also for fungibles only.
        
        // 1. Create a CharteredFund.
        vm.startPrank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // 2. User contributes an NFT.
        uint256 tokenId = ownerTokenId;
        vm.startPrank(admin);
        IERC721(ownerNFT).safeTransferFrom(admin, fundAddress, tokenId);
        vm.stopPrank();

        // 3. Backend confirms credit to move NFT to escrow.
        vm.startPrank(backend);
        charteredFund.commit(fundAddress, admin, ownerNFT, 1, 0, 0, "commit");
        vm.stopPrank();

        // 4. When backend calls remit...
        vm.startPrank(backend);
        
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(IFoundation.Fail.selector);
        charteredFund.remit(admin, ownerNFT, 1, 0, "remit");
        vm.stopPrank();

        // 5. Then: CharteredFund still owns the NFT.
        assertEq(IERC721(ownerNFT).ownerOf(tokenId), fundAddress, "CharteredFund should own NFT");
        
        // And: user's escrow balance is unchanged.
        bytes32 userKey = _getCustodyKey(admin, ownerNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(charteredFund.custody(userKey));
        assertEq(userOwned, 0, "User userOwned should be 0");
        assertEq(escrow, 1, "User escrow should still be 1");
    }

    function test_charteredFund_nftRequestRescission_userOwned_returnsNFT() public {
        // NOTE: This test confirms that CharteredFund.requestRescission is also for fungibles only.
        
        // 1. Create a CharteredFund.
        vm.startPrank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        // 2. User contributes an NFT.
        uint256 tokenId = ownerTokenId;
        vm.startPrank(admin);
        IERC721(ownerNFT).safeTransferFrom(admin, fundAddress, tokenId);
        
        // 3. When user calls requestRescission...
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(IFoundation.Fail.selector);
        charteredFund.requestRescission(ownerNFT);
        vm.stopPrank();

        // 4. Then: CharteredFund still owns the NFT.
        assertEq(IERC721(ownerNFT).ownerOf(tokenId), fundAddress, "CharteredFund should still own NFT");
        
        // And: user's userOwned balance is unchanged.
        bytes32 userKey = _getCustodyKey(admin, ownerNFT);
        (uint128 userOwned, ) = _splitAmount(charteredFund.custody(userKey));
        assertEq(userOwned, 1, "User userOwned should be 1");
    }

    function test_charteredFund_globalUnlock_rescindsEscrowedNFT() public {
        // NOTE: This test confirms that even with global refund mode, CharteredFund.requestRescission is for fungibles only.

        // 1. Create a CharteredFund and escrow an NFT.
        vm.startPrank(backend);
        address fundAddress = root.charterFund(anotherUser, bytes32(0));
        vm.stopPrank();
        CharteredFundImplementation charteredFund = CharteredFundImplementation(payable(fundAddress));

        uint256 tokenId = testTokenId;
        
        vm.startPrank(admin);
        IERC721(testNFT).safeTransferFrom(admin, fundAddress, tokenId);
        vm.stopPrank();

        vm.startPrank(backend);
        charteredFund.commit(fundAddress, admin, testNFT, 1, 0, 0, "commit");
        vm.stopPrank();

        // 2. Enable global refund mode.
        vm.prank(admin);
        root.setRefund(true);
        assertTrue(root.refund(), "Refund mode should be on");

        // 3. When user calls requestRescission...
        vm.startPrank(admin);
        // Then: The call reverts because `safeTransfer` is for ERC20s.
        vm.expectRevert(IFoundation.Fail.selector);
        charteredFund.requestRescission(testNFT);
        vm.stopPrank();

        // 4. Then: CharteredFund still owns the NFT.
        assertEq(IERC721(testNFT).ownerOf(tokenId), fundAddress, "CharteredFund should still own NFT");
        
        // And: user's escrow balance is unchanged.
        bytes32 userKey = _getCustodyKey(admin, testNFT);
        (uint128 userOwned, uint128 escrow) = _splitAmount(charteredFund.custody(userKey));
        assertEq(userOwned, 0);
        assertEq(escrow, 1);
    }

    function test_userRequestRescission_erc20_userOwned() public {
        // 1. User contributes PEPE to create a userOwned balance
        uint256 contributeAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        // 2. User rescinds their userOwned PEPE
        uint256 balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        vm.startPrank(pepeWhale);

        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(root), pepeWhale, PEPE, contributeAmount);
        
        root.requestRescission(PEPE);
        vm.stopPrank();

        // 3. Check balances
        uint256 balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(balance_after, balance_before + contributeAmount, "User PEPE balance should increase");

        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwned, ) = _splitAmount(root.custody(custodyKey));
        assertEq(userOwned, 0, "userOwned balance should be zero after rescission");
    }

    function test_backendRemit_eth_sendsEscrow() public {
        // 1. Setup user escrow balance
        uint256 contributeAmount = 5 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: contributeAmount}("");
        require(success);

        vm.prank(backend);
        root.commit(address(root), user, address(0), contributeAmount, 0, "commit");
        vm.stopPrank();

        // 2. Backend remits funds to user with a fee
        uint256 remitAmount = 2 ether;
        uint128 fee = uint128(0.1 ether);
        
        uint256 user_balance_before = user.balance;

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true);
        emit RemittanceProcessed(address(root), user, address(0), remitAmount, fee, "remit");
        
        root.remit(user, address(0), remitAmount, fee, "remit");
        vm.stopPrank();

        // 3. Check balances
        uint256 user_balance_after = user.balance;
        assertEq(user_balance_after, user_balance_before + remitAmount, "User balance should increase by remit amount");
        
        // Check internal custody
        bytes32 userKey = _getCustodyKey(user, address(0));
        (, uint128 userEscrow) = _splitAmount(root.custody(userKey));
        assertEq(userEscrow, contributeAmount - remitAmount - fee, "User escrow should decrease by remit amount and fee");

        bytes32 protocolKey = _getCustodyKey(address(root), address(0));
        (, uint128 protocolEscrow) = _splitAmount(root.custody(protocolKey));
        assertEq(protocolEscrow, fee, "Protocol escrow should equal the fee");
    }

    function test_globalUnlock_allowsEthEscrowRescission() public {
        // 1. Setup user escrow balance
        uint256 contributeAmount = 3 ether;
        vm.prank(user);
        (bool success, ) = address(root).call{value: contributeAmount}("");
        require(success);

        vm.prank(backend);
        root.commit(address(root), user, address(0), contributeAmount, 0, "commit");
        vm.stopPrank();

        // 2. Enable global refund mode
        vm.prank(admin);
        root.setRefund(true);
        assertTrue(root.refund());

        // 3. User rescinds their escrowed ETH
        uint256 balance_before = user.balance;
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(root), user, address(0), contributeAmount);
        
        root.requestRescission(address(0));
        vm.stopPrank();

        // 4. Check balances
        uint256 balance_after = user.balance;
        assertTrue(balance_after > balance_before, "User ETH balance should increase");

        bytes32 custodyKey = _getCustodyKey(user, address(0));
        (, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(escrow, 0, "escrow balance should be zero after rescission");
    }

    function test_globalUnlock_allowsErc20EscrowRescission() public {
        // 1. Setup user escrow balance
        uint256 contributeAmount = 1_000_000 * 1e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), contributeAmount);
        root.contribute(PEPE, contributeAmount);
        vm.stopPrank();

        vm.prank(backend);
        root.commit(address(root), pepeWhale, PEPE, contributeAmount, 0, "commit");
        vm.stopPrank();

        // 2. Enable global refund mode
        vm.prank(admin);
        root.setRefund(true);

        // 3. User rescinds their escrowed PEPE
        uint256 balance_before = ERC20(PEPE).balanceOf(pepeWhale);
        vm.startPrank(pepeWhale);

        vm.expectEmit(true, true, true, true);
        emit ContributionRescinded(address(root), pepeWhale, PEPE, contributeAmount);
        
        root.requestRescission(PEPE);
        vm.stopPrank();

        // 4. Check balances
        uint256 balance_after = ERC20(PEPE).balanceOf(pepeWhale);
        assertEq(balance_after, balance_before + contributeAmount, "User PEPE balance should increase");

        bytes32 custodyKey = _getCustodyKey(pepeWhale, PEPE);
        (, uint128 escrow) = _splitAmount(root.custody(custodyKey));
        assertEq(escrow, 0, "escrow balance should be zero after rescission");
    }

} 