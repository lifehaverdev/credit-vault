// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ICreateX} from "lib/createx-forge/script/ICreateX.sol";
import {CREATEX_ADDRESS, CREATEX_BYTECODE} from "lib/createx-forge/script/CreateX.d.sol";

// -----------------------------------------------------------------------------
//                              DUMMY CONTRACTS
// -----------------------------------------------------------------------------

contract Dummy {
    function foo(uint256) external {}
}

contract DummyWithFoo {
    function foo(uint256) external {}
    function bar() external {}
}

/// @title CreateXDeterminismTest
/// @notice Demonstrates that for the project’s guarded-salt CREATE3 workflow,
///         the deployed address depends **only** on `factory` + `salt`.
///         Implementation bytecode, init calldata, caller address, and its
///         nonce are written *after* deployment and therefore do **not** affect
///         the CREATE3 address.
contract CreateXDeterminismTest is Test {
    /* ------------------------------------------------------------------------ */
    /*                               CONSTANTS                                  */
    /* ------------------------------------------------------------------------ */

    // Raw user-supplied salt (fits within the allowed 88-bit range).
    bytes32 internal constant RAW_SALT = bytes32(uint256(123456));

    // Cached interface to the on-chain CreateX factory.
    ICreateX internal constant _createx = ICreateX(CREATEX_ADDRESS);

    /* ------------------------------------------------------------------------ */
    /*                                   SETUP                                  */
    /* ------------------------------------------------------------------------ */

    function setUp() public {
        // Select the default fork (mainnet) from foundry.toml rpc_endpoints.
        vm.createSelectFork(vm.rpcUrl("mainnet"));

        // Ensure the CreateX factory bytecode is present on this fork.
        if (CREATEX_ADDRESS.code.length == 0) {
            vm.etch(CREATEX_ADDRESS, CREATEX_BYTECODE);
        }
    }

    /* ------------------------------------------------------------------------ */
    /*                               INTERNALS                                  */
    /* ------------------------------------------------------------------------ */

    /// @dev Computes the guarded salt as specified by the deployment mode.
    function _guardedSalt() internal pure returns (bytes32) {
        // For a rawSalt with first 20 bytes == 0 and 21st byte == 0x00 (no extra guard flags),
        // CreateX._guard hashes the salt directly (see CreateX.sol::_guard fall-back branch).
        return keccak256(abi.encode(RAW_SALT));
    }

    /// @dev Predicts the CREATE3 address for the given guarded salt.
    function _predict() internal view returns (address) {
        return _createx.computeCreate3Address(_guardedSalt(), CREATEX_ADDRESS);
    }

    /// @dev Deploys a contract through CreateX using the RAW_SALT.  The VM
    ///      state is reverted afterwards so the same salt can be reused.
    function _deploy(bytes memory initCode, bytes memory initData, address caller) internal returns (address deployed) {
        uint256 snap = vm.snapshot();
        vm.startPrank(caller);
        deployed = _createx.deployCreate3AndInit(RAW_SALT, initCode, initData, ICreateX.Values(0, 0));
        vm.stopPrank();
        vm.revertTo(snap);
    }

    /* ------------------------------------------------------------------------ */
    /*                                   TESTS                                  */
    /* ------------------------------------------------------------------------ */

    /// @notice Deployed address is independent of implementation bytecode.
    function test_ImplementationIrrelevant() external {
        bytes memory codeA = type(Dummy).creationCode;
        bytes memory codeB = type(DummyWithFoo).creationCode;

        address predicted = _predict();

        bytes memory init = abi.encodeWithSignature("foo(uint256)", 1);

        address depA = _deploy(codeA, init, address(0xBEEF));
        assertEq(depA, predicted, "deployment A mismatch");

        address depB = _deploy(codeB, init, address(0xBEEF));
        assertEq(depB, predicted, "deployment B mismatch");
    }

    /// @notice Deployed address is independent of initialise calldata.
    function test_CalldataIrrelevant() external {
        bytes memory code = type(DummyWithFoo).creationCode;
        address predicted = _predict();

        bytes memory initA = abi.encodeWithSignature("foo(uint256)", 1);
        bytes memory initB = abi.encodeWithSignature("foo(uint256)", 42);

        address depA = _deploy(code, initA, address(0xBEEF));
        assertEq(depA, predicted, "deploy A mismatch");

        address depB = _deploy(code, initB, address(0xBEEF));
        assertEq(depB, predicted, "deploy B mismatch");
    }

    /// @notice Deployed address is independent of caller address and its nonce.
    function test_CallerAndNonceIrrelevant() external {
        bytes memory code = type(Dummy).creationCode;
        address predicted = _predict();

        // Caller #1 at nonce-0.
        bytes memory init = abi.encodeWithSignature("foo(uint256)", 1);
        address dep1 = _deploy(code, init, address(0xCAFE));
        assertEq(dep1, predicted, "caller 1 mismatch");

        // Caller #2 bumps its nonce with dummy txs then deploys.
        address caller2 = address(0xDEAD);
        vm.deal(caller2, 1 ether);
        vm.prank(caller2);
        payable(caller2).transfer(0);
        vm.prank(caller2);
        payable(caller2).transfer(0);

        address dep2 = _deploy(code, init, caller2);
        assertEq(dep2, predicted, "caller 2 mismatch");
    }
}
