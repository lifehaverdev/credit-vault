// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {ICreateX} from "lib/createx-forge/script/ICreateX.sol";
import {CREATEX_ADDRESS, CREATEX_BYTECODE} from "lib/createx-forge/script/CreateX.d.sol";
import {IFoundation} from "../src/interfaces/IFoundation.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @dev Simulates a chartered fund calling recordContribution with ETH attached.
///      Uses a low-level call so we can attach value regardless of the interface's payability.
contract MockCharteredFundCaller {
    address public foundation;
    constructor(address _foundation) { foundation = _foundation; }
    function callWithValue(address user, address token, uint256 amount) external payable {
        bytes memory data = abi.encodeWithSignature(
            "recordContribution(address,address,uint256)",
            user, token, amount
        );
        (bool ok, ) = foundation.call{value: msg.value}(data);
        require(ok, "call failed");
    }
}

contract SecurityFixesTest is Test {
    Foundation root;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;

    address private constant MILADYSTATION = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    address ownerNFT;
    uint256 ownerTokenId;
    address charterBeacon;

    // Different suffix from other test suites to avoid CREATE3 address collision.
    uint88 private constant SALT_SUFFIX = 912;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        backend = makeAddr("backend");
        user    = makeAddr("user");

        vm.deal(admin, 10 ether);
        vm.deal(user, 10 ether);

        address cfImpl = address(new CharteredFundImplementation());
        charterBeacon = address(new UpgradeableBeacon(admin, cfImpl));

        ownerNFT    = MILADYSTATION;
        ownerTokenId = 598;
        vm.mockCall(ownerNFT, abi.encodeWithSelector(0x6352211e, ownerTokenId), abi.encode(admin));

        if (CREATEX_ADDRESS.code.length == 0) {
            vm.etch(CREATEX_ADDRESS, CREATEX_BYTECODE);
        }

        address impl = address(new Foundation());
        bytes memory proxyInitCode = LibClone.initCodeERC1967(impl);
        bytes32 rawSalt      = bytes32((uint256(1) << 88) | uint256(SALT_SUFFIX));
        bytes32 guardedSalt  = keccak256(abi.encode(block.chainid, rawSalt));
        address predictedProxy = ICreateX(CREATEX_ADDRESS).computeCreate3Address(guardedSalt, CREATEX_ADDRESS);

        vm.startPrank(admin);
        ICreateX(CREATEX_ADDRESS).deployCreate3AndInit(
            rawSalt,
            proxyInitCode,
            abi.encodeWithSelector(Foundation.initialize.selector, ownerNFT, ownerTokenId, charterBeacon),
            ICreateX.Values(0, 0)
        );
        root = Foundation(payable(predictedProxy));
        root.setMarshal(backend, true);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Fix 1: onlyOwner should revert Auth() when the NFT call returns empty
    //
    // Currently: abi.decode("", (address)) throws a generic ABI decode error,
    //            not the Auth() custom error — expectRevert(Auth.selector) fails.
    // After fix: staticcall + data.length == 0 check reverts with Auth().
    // ────────────────────────────────────────────────────────────────────────
    function test_onlyOwner_revertsAuth_whenNFTCallReturnsEmpty() public {
        vm.mockCall(ownerNFT, abi.encodeWithSelector(0x6352211e, ownerTokenId), "");
        vm.prank(user);
        vm.expectRevert(IFoundation.Auth.selector);
        root.setMarshal(makeAddr("newMarshal"), true);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Fix 3: recordContribution must not be payable
    //
    // Currently: function is payable, so calling it with ETH succeeds.
    // After fix:  non-payable, so any value causes an EVM revert.
    // ────────────────────────────────────────────────────────────────────────
    function test_recordContribution_rejectsEtherValue() public {
        // Register mock as a chartered fund by writing directly to the
        // isCharteredFund mapping (slot 1: Keep.custody is slot 0).
        MockCharteredFundCaller mock = new MockCharteredFundCaller(address(root));
        bytes32 mappingSlot = keccak256(abi.encode(address(mock), uint256(1)));
        vm.store(address(root), mappingSlot, bytes32(uint256(1)));

        vm.deal(address(mock), 1 ether);
        vm.expectRevert();
        mock.callWithValue{value: 1}(user, address(0), 1);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Fix 4: contribute must revert when amount exceeds uint128 max
    //
    // Currently: uint128(amount) silently truncates — tokens transfer but
    //            custody credits the wrong (truncated) amount. No revert.
    // After fix:  reverts with Math() before any transfer occurs.
    // ────────────────────────────────────────────────────────────────────────
    function test_contribute_revertsWhenAmountExceedsUint128Max() public {
        uint256 tooLarge = uint256(type(uint128).max) + 1;
        deal(PEPE, user, tooLarge);

        vm.startPrank(user);
        ERC20(PEPE).approve(address(root), tooLarge);
        vm.expectRevert(IFoundation.Math.selector);
        root.contribute(PEPE, tooLarge);
        vm.stopPrank();
    }

    // ────────────────────────────────────────────────────────────────────────
    // Fix 5: Foundation.commit with fee must preserve protocolOwned
    //
    // Currently: (, uint128 accountEscrow) discards accountOwned, then
    //            _packAmount(0, accountEscrow + fee) zeroes protocolOwned.
    //            Any prior donation is silently wiped.
    // After fix:  reads both slots and writes _packAmount(accountOwned, accountEscrow + fee).
    // ────────────────────────────────────────────────────────────────────────
    function test_commit_withFee_preservesProtocolOwned() public {
        // 1. User contributes ETH so there is something to commit.
        uint256 userDeposit = 2 ether;
        vm.prank(user);
        (bool ok,) = address(root).call{value: userDeposit}("");
        require(ok);

        // 2. Donate ETH directly to the protocol — establishes protocolOwned.
        uint256 donation = 0.5 ether;
        vm.prank(admin);
        root.donate{value: donation}(address(0), donation, bytes32(0), false);

        bytes32 protocolKey = keccak256(abi.encodePacked(address(root), address(0)));
        (uint128 ownedBefore,) = _splitSlot(root.custody(protocolKey));
        assertEq(ownedBefore, donation, "protocolOwned must equal donation before commit");

        // 3. Backend commits half the user's balance, charging a fee from the remainder.
        uint128 fee = 0.1 ether;
        uint256 escrowAmount = 1 ether; // leaves 1 ether remaining owned, fee < remainder
        vm.prank(backend);
        root.commit(address(root), user, address(0), escrowAmount, fee, "withFee");

        // 4. protocolOwned must be unchanged — only protocolEscrow should grow.
        (uint128 ownedAfter, uint128 escrowAfter) = _splitSlot(root.custody(protocolKey));
        assertEq(ownedAfter,  ownedBefore, "protocolOwned must NOT be zeroed by commit");
        assertEq(escrowAfter, fee,         "protocolEscrow must equal the fee taken");
    }

    function _splitSlot(bytes32 v) internal pure returns (uint128 owned, uint128 escrow) {
        owned  = uint128(uint256(v));
        escrow = uint128(uint256(v >> 128));
    }
}
