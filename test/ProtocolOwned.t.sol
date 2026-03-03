// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {TestToken} from "./mocks/TestToken.sol";

/// @notice Tests for Foundation.withdrawProtocolOwned —
///         the extraction path for custody[Foundation][token].owned funds
///         (donations and recoverProtocolOwned credits) that previously
///         had no way to leave the contract.
contract ProtocolOwnedTest is Test {
    Foundation root;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;

    function setUp() public {
        backend = makeAddr("backend");
        vm.deal(admin, 10 ether);
        vm.deal(address(this), 10 ether);

        address cfImpl       = address(new CharteredFundImplementation());
        address charterBeacon = address(new UpgradeableBeacon(admin, cfImpl));

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
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    function _getCustodyKey(address u, address t) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(u, t));
    }

    function _splitAmount(bytes32 v) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(v));
        escrow = uint128(uint256(v >> 128));
    }

    /// @dev Seeds protocolOwned via ETH donation from this test contract.
    function _seedETHOwned(uint256 amount) internal {
        root.donate{value: amount}(address(0), amount, bytes32(0), false);
    }

    // ── ETH tests ─────────────────────────────────────────────────────────────

    /// @notice Owner can withdraw ETH from protocolOwned to their wallet.
    function test_withdrawProtocolOwned_ethSendsToOwner() public {
        uint256 donated = 1 ether;
        _seedETHOwned(donated);

        uint256 adminBalBefore = admin.balance;

        vm.prank(admin);
        root.withdrawProtocolOwned(address(0), donated);

        assertEq(admin.balance, adminBalBefore + donated, "owner must receive ETH");

        (uint128 owned, ) = _splitAmount(root.custody(_getCustodyKey(address(root), address(0))));
        assertEq(owned, 0, "protocolOwned must be zero after full withdrawal");
    }

    /// @notice Partial withdrawal leaves the remainder in protocolOwned.
    function test_withdrawProtocolOwned_partialEthLeavesRemainder() public {
        uint256 donated  = 2 ether;
        uint256 withdraw = 0.7 ether;
        _seedETHOwned(donated);

        vm.prank(admin);
        root.withdrawProtocolOwned(address(0), withdraw);

        (uint128 owned, ) = _splitAmount(root.custody(_getCustodyKey(address(root), address(0))));
        assertEq(owned, donated - withdraw, "remainder must stay in protocolOwned");
    }

    /// @notice Non-owner (even a marshal) cannot call withdrawProtocolOwned.
    function test_withdrawProtocolOwned_revertsForNonOwner() public {
        _seedETHOwned(1 ether);
        vm.prank(backend);
        vm.expectRevert(bytes4(keccak256("Auth()")));
        root.withdrawProtocolOwned(address(0), 1 ether);
    }

    /// @notice Reverts Math() when requested amount exceeds protocolOwned.
    function test_withdrawProtocolOwned_revertsOnInsufficientOwned() public {
        _seedETHOwned(0.5 ether);
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("Math()")));
        root.withdrawProtocolOwned(address(0), 1 ether);
    }

    /// @notice Withdrawing zero reverts Math() (nothing to send).
    function test_withdrawProtocolOwned_revertsOnZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("Math()")));
        root.withdrawProtocolOwned(address(0), 0);
    }

    // ── ERC20 tests ───────────────────────────────────────────────────────────

    /// @notice Owner can withdraw ERC20 tokens from protocolOwned.
    function test_withdrawProtocolOwned_erc20SendsToOwner() public {
        TestToken tok = new TestToken();
        uint256 donated = 500e18;

        // Donate ERC20 to foundation (goes to protocolOwned)
        tok.approve(address(root), donated);
        root.donate(address(tok), donated, bytes32(0), false);

        uint256 ownerBalBefore = tok.balanceOf(admin);

        vm.prank(admin);
        root.withdrawProtocolOwned(address(tok), donated);

        assertEq(tok.balanceOf(admin), ownerBalBefore + donated, "owner must receive ERC20");

        (uint128 owned, ) = _splitAmount(root.custody(_getCustodyKey(address(root), address(tok))));
        assertEq(owned, 0, "protocolOwned ERC20 must be zero after withdrawal");
    }

    // ── Non-interference with escrow ──────────────────────────────────────────

    /// @notice withdrawProtocolOwned does NOT touch protocolEscrow.
    function test_withdrawProtocolOwned_doesNotTouchEscrow() public {
        uint256 donated  = 1 ether;
        uint256 userDep  = 2 ether; // 2 ETH so commit(1, fee=1) is valid
        address user1    = makeAddr("user1");
        vm.deal(user1, 3 ether);

        // Seed protocolOwned via donation
        _seedETHOwned(donated);

        // Seed protocolEscrow via commit-with-fee:
        // user deposits 2 ETH → ownedBefore=2; commit(escrow=1, fee=1) → remaining=1 ≥ fee=1 ✓
        vm.prank(user1);
        (bool ok,) = address(root).call{value: userDep}("");
        require(ok);
        vm.prank(backend);
        root.commit(address(root), user1, address(0), 1 ether, uint128(1 ether), "");

        (, uint128 escrowBefore) = _splitAmount(root.custody(_getCustodyKey(address(root), address(0))));

        // Withdraw protocolOwned
        vm.prank(admin);
        root.withdrawProtocolOwned(address(0), donated);

        (, uint128 escrowAfter) = _splitAmount(root.custody(_getCustodyKey(address(root), address(0))));
        assertEq(escrowAfter, escrowBefore, "protocolEscrow must be unchanged");
    }
}
