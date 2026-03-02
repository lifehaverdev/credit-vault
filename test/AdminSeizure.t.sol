// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {VanitySalt} from "./utils/VanitySalt.sol";

/// @notice Integration tests for admin seizure (commit+remit Liquidation path).
contract AdminSeizureTest is Test {
    Foundation root;
    CharteredFundImplementation fund;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user1;
    address user2;
    address fundOwner;
    address charterBeacon;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        backend  = makeAddr("backend");
        user1    = makeAddr("user1");
        user2    = makeAddr("user2");
        fundOwner = makeAddr("fundOwner");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(fundOwner, 10 ether);

        // Deploy
        address cfImpl = address(new CharteredFundImplementation());
        charterBeacon = address(new UpgradeableBeacon(admin, cfImpl));

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

        // Charter one fund
        bytes memory args = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            address(root),
            fundOwner
        );
        bytes32 salt = VanitySalt.mine(charterBeacon, args, address(root), 1_000_000);
        vm.prank(backend);
        fund = CharteredFundImplementation(payable(root.charterFund(fundOwner, salt)));
    }

    function _getCustodyKey(address u, address t) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(u, t));
    }

    function _splitAmount(bytes32 v) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(v));
        escrow = uint128(uint256(v >> 128));
    }

    /// @notice Full admin seizure from Foundation: commit(fee=0) then remit(amount=0, fee=seizure).
    /// Verifies that Liquidation event fires, depositor escrow is zeroed,
    /// protocol.escrow accumulates, and allocate+remit pays admin.
    function test_foundation_adminSeizure_multicall() public {
        uint256 user1Deposit = 1 ether;
        uint256 user2Deposit = 0.5 ether;
        uint256 total = user1Deposit + user2Deposit;

        // Users deposit ETH
        vm.prank(user1);
        (bool ok1,) = address(root).call{value: user1Deposit}("");
        require(ok1);

        vm.prank(user2);
        (bool ok2,) = address(root).call{value: user2Deposit}("");
        require(ok2);

        uint256 adminBalBefore = backend.balance;

        // Build multicall
        bytes[] memory calls = new bytes[](6);
        calls[0] = abi.encodeCall(Foundation.commit, (address(root), user1, address(0), user1Deposit, 0, "ADMIN_SEIZURE"));
        calls[1] = abi.encodeCall(Foundation.remit,  (user1, address(0), 0, uint128(user1Deposit), "ADMIN_SEIZURE"));
        calls[2] = abi.encodeCall(Foundation.commit, (address(root), user2, address(0), user2Deposit, 0, "ADMIN_SEIZURE"));
        calls[3] = abi.encodeCall(Foundation.remit,  (user2, address(0), 0, uint128(user2Deposit), "ADMIN_SEIZURE"));
        calls[4] = abi.encodeCall(Foundation.allocate, (backend, address(0), total));
        calls[5] = abi.encodeCall(Foundation.remit,    (backend, address(0), total, 0, "ADMIN_WITHDRAWAL"));

        // Expect Liquidation events
        vm.expectEmit(true, true, true, true, address(root));
        emit Foundation.Liquidation(address(root), user1, address(0), user1Deposit, "ADMIN_SEIZURE");
        vm.expectEmit(true, true, true, true, address(root));
        emit Foundation.Liquidation(address(root), user2, address(0), user2Deposit, "ADMIN_SEIZURE");

        vm.prank(backend, backend);
        root.multicall(calls);

        // Admin received ETH
        assertEq(backend.balance, adminBalBefore + total, "admin must receive seized ETH");

        // User escrows zeroed
        (, uint128 u1esc) = _splitAmount(root.custody(_getCustodyKey(user1, address(0))));
        (, uint128 u2esc) = _splitAmount(root.custody(_getCustodyKey(user2, address(0))));
        assertEq(u1esc, 0, "user1 escrow must be zero after seizure");
        assertEq(u2esc, 0, "user2 escrow must be zero after seizure");
    }

    /// @notice Full admin seizure from a chartered fund using direct charterFund.multicall.
    /// Marshal calls the charter fund directly — no need to go through Foundation.
    function test_charteredFund_adminSeizure_multicall() public {
        uint256 deposit = 1 ether;

        // User deposits into charter fund
        vm.prank(user1);
        (bool ok,) = address(fund).call{value: deposit}("");
        require(ok);

        uint256 adminBalBefore = backend.balance;

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(CharteredFundImplementation.commit,
            (address(fund), user1, address(0), deposit, 0, 0, "ADMIN_SEIZURE"));
        calls[1] = abi.encodeCall(CharteredFundImplementation.remit,
            (user1, address(0), 0, uint128(deposit), "ADMIN_SEIZURE"));
        calls[2] = abi.encodeCall(CharteredFundImplementation.allocate,
            (backend, address(0), deposit));
        calls[3] = abi.encodeCall(CharteredFundImplementation.remit,
            (backend, address(0), deposit, 0, "ADMIN_WITHDRAWAL"));

        vm.prank(backend, backend);
        fund.multicall(calls);

        assertEq(backend.balance, adminBalBefore + deposit, "admin must receive charter fund ETH");

        (, uint128 esc) = _splitAmount(fund.custody(_getCustodyKey(user1, address(0))));
        assertEq(esc, 0, "user1 charter fund escrow must be zero");
    }
}
