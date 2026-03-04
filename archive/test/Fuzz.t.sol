// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {VanitySalt} from "./utils/VanitySalt.sol";

/// @notice Fuzz tests for core invariants of the Keep/Foundation custody system.
///         Uses a local deployment (no mainnet fork) to maximise fuzz speed.
contract FuzzTest is Test {

    Foundation root;
    CharteredFundImplementation fund;

    address admin;
    address backend;
    address charterBeacon;

    function setUp() public {
        admin   = makeAddr("admin");
        backend = makeAddr("backend");

        vm.deal(admin,   100 ether);
        vm.deal(backend, 100 ether);

        // ── Deploy fresh Foundation (no mainnet fork) ──────────────────────
        address cfImpl = address(new CharteredFundImplementation());
        charterBeacon  = address(new UpgradeableBeacon(admin, cfImpl));

        MockERC721 nft = new MockERC721();
        nft.mint(admin, 1);
        vm.mockCall(address(nft), abi.encodeWithSelector(0x6352211e, uint256(1)), abi.encode(admin));

        address proxy = new ERC1967Factory().deploy(address(new Foundation()), admin);
        root = Foundation(payable(proxy));

        vm.startPrank(admin);
        root.initialize(address(nft), 1, charterBeacon);
        UpgradeableBeacon(charterBeacon).transferOwnership(address(root));
        root.setMarshal(backend, true);
        vm.stopPrank();

        // ── Charter one fund ───────────────────────────────────────────────
        bytes memory args = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            address(root),
            admin
        );
        bytes32 salt = VanitySalt.mine(charterBeacon, args, address(root), 1_000_000);
        vm.prank(backend);
        fund = CharteredFundImplementation(payable(root.charterFund(admin, salt)));
    }

    // ────────────────────────────────────────────────────────────────────────
    // Pack / unpack roundtrip
    // ────────────────────────────────────────────────────────────────────────

    /// @notice _packAmount then _splitAmount must recover the original values.
    function testFuzz_packUnpack_roundtrip(uint128 owned, uint128 escrow) public pure {
        bytes32 packed = _packAmount(owned, escrow);
        (uint128 gotOwned, uint128 gotEscrow) = _splitAmount(packed);
        assertEq(gotOwned,  owned,  "owned roundtrip failed");
        assertEq(gotEscrow, escrow, "escrow roundtrip failed");
    }

    // ────────────────────────────────────────────────────────────────────────
    // ETH balance invariant
    // ────────────────────────────────────────────────────────────────────────

    /// @notice After an ETH contribution, the contract's balance must increase
    ///         by exactly the deposited amount, and the custody slot must reflect it.
    function testFuzz_ethContribute_balanceInvariant(uint128 amount) public {
        amount = uint128(bound(uint256(amount), 1, 100 ether));

        address depositor = makeAddr("depositor");
        vm.deal(depositor, amount);

        uint256 contractBefore = address(root).balance;

        vm.prank(depositor);
        (bool ok,) = address(root).call{value: amount}("");
        assertTrue(ok);

        assertEq(address(root).balance, contractBefore + amount, "contract ETH balance must grow by deposit");

        bytes32 key = _getCustodyKey(depositor, address(0));
        (uint128 owned,) = _splitAmount(root.custody(key));
        assertEq(owned, amount, "custody slot must equal deposited amount");
    }

    // ────────────────────────────────────────────────────────────────────────
    // commit accounting invariant
    // ────────────────────────────────────────────────────────────────────────

    /// @notice commit moves exactly escrowAmount from userOwned to escrow; total is conserved.
    function testFuzz_commit_accountingInvariant(uint128 deposit, uint8 escrowPct) public {
        deposit    = uint128(bound(uint256(deposit), 1 ether, 50 ether));
        uint256 escrowAmt = (uint256(deposit) * bound(uint256(escrowPct), 1, 100)) / 100;

        address depositor = makeAddr("fuzzDepositor");
        vm.deal(depositor, deposit);

        vm.prank(depositor);
        (bool ok,) = address(root).call{value: deposit}("");
        assertTrue(ok);

        bytes32 key = _getCustodyKey(depositor, address(0));
        (uint128 ownedBefore, uint128 escrowBefore) = _splitAmount(root.custody(key));

        vm.prank(backend);
        root.commit(address(root), depositor, address(0), escrowAmt, 0, "fuzz");

        (uint128 ownedAfter, uint128 escrowAfter) = _splitAmount(root.custody(key));

        // Total conserved
        assertEq(uint256(ownedAfter) + uint256(escrowAfter),
                 uint256(ownedBefore) + uint256(escrowBefore),
                 "total balance must be conserved through commit");

        // Owned decreases by exactly escrowAmt
        assertEq(ownedAfter,  ownedBefore  - uint128(escrowAmt), "owned must decrease by escrowAmt");
        assertEq(escrowAfter, escrowBefore + uint128(escrowAmt), "escrow must increase by escrowAmt");
    }

    // ────────────────────────────────────────────────────────────────────────
    // remit accounting invariant
    // ────────────────────────────────────────────────────────────────────────

    /// @notice After remit(amount, fee), user's escrow decreases by amount+fee,
    ///         protocol's escrow increases by fee, and the contract pays amount to user.
    function testFuzz_remit_accounting(uint128 deposit, uint8 paymentPct, uint8 feePct) public {
        deposit = uint128(bound(uint256(deposit), 2 ether, 50 ether));

        // Keep total payment+fee ≤ deposit
        uint256 maxPayment = (uint256(deposit) * bound(uint256(paymentPct), 1, 49)) / 100;
        uint256 maxFee     = (uint256(deposit) * bound(uint256(feePct), 1, 49)) / 100;
        // Ensure they fit
        if (maxPayment + maxFee > deposit) maxFee = deposit - maxPayment;

        address depositor = makeAddr("fuzzRemitDepositor");
        vm.deal(depositor, deposit);
        // Ensure depositor can receive ETH (it's a fresh make-addr, no code)
        vm.etch(depositor, bytes(""));

        vm.prank(depositor);
        (bool ok,) = address(root).call{value: deposit}("");
        assertTrue(ok);

        // Commit full balance to escrow
        vm.prank(backend);
        root.commit(address(root), depositor, address(0), deposit, 0, "");

        bytes32 userKey     = _getCustodyKey(depositor, address(0));
        bytes32 protocolKey = _getCustodyKey(address(root), address(0));

        (, uint128 userEscBefore)     = _splitAmount(root.custody(userKey));
        (, uint128 protocolEscBefore) = _splitAmount(root.custody(protocolKey));
        uint256 depositorEthBefore    = depositor.balance;

        vm.prank(backend);
        root.remit(depositor, address(0), maxPayment, uint128(maxFee), "fuzzRemit");

        (, uint128 userEscAfter)     = _splitAmount(root.custody(userKey));
        (, uint128 protocolEscAfter) = _splitAmount(root.custody(protocolKey));

        uint256 totalDeducted = maxPayment + maxFee;
        assertEq(uint256(userEscBefore) - uint256(userEscAfter), totalDeducted,
            "user escrow must decrease by payment+fee");

        assertEq(uint256(protocolEscAfter) - uint256(protocolEscBefore), maxFee,
            "protocol escrow must increase by fee");

        assertEq(depositor.balance, depositorEthBefore + maxPayment,
            "depositor must receive exactly the payment amount");
    }

    // ────────────────────────────────────────────────────────────────────────
    // contribute uint128 overflow guard
    // ────────────────────────────────────────────────────────────────────────

    /// @notice Any amount > uint128 max must revert with Math() before transfer.
    function testFuzz_contribute_overflowReverts(uint256 overflowExtra) public {
        // Make overflowExtra in range [1, type(uint128).max] so the total overflows uint128
        overflowExtra = bound(overflowExtra, 1, type(uint128).max);
        uint256 tooLarge = uint256(type(uint128).max) + overflowExtra;

        address depositor = makeAddr("overflowDepositor");
        vm.deal(depositor, tooLarge);

        vm.prank(depositor);
        vm.expectRevert(bytes4(keccak256("Math()")));
        address(root).call{value: tooLarge}("");
    }

    // ────────────────────────────────────────────────────────────────────────
    //  Helpers (mirrors Keep internals without inheritance)
    // ────────────────────────────────────────────────────────────────────────

    function _getCustodyKey(address u, address t) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(u, t));
    }

    function _packAmount(uint128 owned, uint128 escrow) internal pure returns (bytes32) {
        return bytes32(uint256(owned) | (uint256(escrow) << 128));
    }

    function _splitAmount(bytes32 v) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(v));
        escrow = uint128(uint256(v >> 128));
    }
}
