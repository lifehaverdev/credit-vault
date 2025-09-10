// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ProxyDeterminismTest
/// @notice Demonstrates that for `ERC1967Factory.deployDeterministicAndCall`,
///         the proxy address depends **only** on `factory` + `salt`.
///         Implementation address, admin address, caller address / nonce, and
///         `initialize()` calldata are all written *after* deployment and do
///         not affect the CREATE2 address (it is
///         `keccak256(0xff‖factory‖salt‖factory.initCodeHash())[12:]`).

import "forge-std/Test.sol";
import {ERC1967Factory} from "lib/solady/src/utils/ERC1967Factory.sol";

// Simple empty contract to act as dummy implementation target.
contract Dummy {}

// Implementation that accepts an arbitrary uint256 via foo to allow non-empty
// init calldata without reverting.
contract DummyWithFoo {
    function foo(uint256) external {}
}

contract ProxyDeterminismTest is Test {
    /* --------------------------------------------------------------------- */
    /*                               SETTINGS                                */
    /* --------------------------------------------------------------------- */

    bytes32 internal constant SALT = bytes32(uint256(123456)); // top-96-bits == 0

    // Deploy a fresh factory for an isolated playground.
    ERC1967Factory internal factory;

    // Dummy implementation instances created during tests.

    function setUp() public {
        factory = new ERC1967Factory();
    }

    /* --------------------------------------------------------------------- */
    /*                               INTERNALS                                */
    /* --------------------------------------------------------------------- */

    function _predict() internal view returns (address) {
        return factory.predictDeterministicAddress(SALT);
    }

    function _deploy(
        address implementation,
        address admin,
        bytes memory initCalldata,
        address caller
    ) internal returns (address deployed) {
        uint256 snap = vm.snapshot();
        vm.startPrank(caller);
        deployed = address(factory.deployDeterministicAndCall(implementation, admin, SALT, initCalldata));
        vm.stopPrank();
        vm.revertTo(snap); // Rewind so we can reuse the `salt` in later cases.
    }

    /* --------------------------------------------------------------------- */
    /*                                 TESTS                                  */
    /* --------------------------------------------------------------------- */

    /// @notice Proxy address is independent of implementation address.
    function test_ImplementationIrrelevant() external {
        address impl1 = address(new Dummy());
        address impl2 = address(new Dummy());

        address predicted = _predict();

        address dep1 = _deploy(impl1, address(0xA1), new bytes(0), address(0xBEEF));
        assertEq(dep1, predicted, "deployment 1 mismatch");

        address dep2 = _deploy(impl2, address(0xA1), new bytes(0), address(0xBEEF));
        assertEq(dep2, predicted, "deployment 2 mismatch");
    }

    /// @notice Proxy address is independent of initialize calldata.
    function test_CalldataIrrelevant() external {
        address impl = address(new DummyWithFoo());
        address predicted = _predict();

        bytes memory initA = new bytes(0);
        bytes memory initB = abi.encodeWithSignature("foo(uint256)", 42);

        address depA = _deploy(impl, address(0xA1), initA, address(0xBEEF));
        assertEq(depA, predicted, "deploy A mismatch");

        address depB = _deploy(impl, address(0xA1), initB, address(0xBEEF));
        assertEq(depB, predicted, "deploy B mismatch");
    }

    /// @notice Proxy address is independent of admin address.
    function test_AdminIrrelevant() external {
        address impl = address(new Dummy());
        address predicted = _predict();

        address depA = _deploy(impl, address(0xA1), new bytes(0), address(0xBEEF));
        assertEq(depA, predicted, "admin A mismatch");

        address depB = _deploy(impl, address(0xA2), new bytes(0), address(0xBEEF));
        assertEq(depB, predicted, "admin B mismatch");
    }

    /// @notice Proxy address is independent of the caller address and its nonce.
    function test_CallerAndNonceIrrelevant() external {
        address impl = address(new Dummy());
        address predicted = _predict();

        // Caller #1 at nonce-0.
        address dep1 = _deploy(impl, address(0xA1), new bytes(0), address(0xCAFE));
        assertEq(dep1, predicted, "caller 1 mismatch");

        // Caller #2 perform some random txs to bump its nonce, then deploy.
        address caller2 = address(0xDEAD);
        vm.deal(caller2, 1 ether);
        vm.prank(caller2);
        payable(caller2).transfer(0); // dummy tx increments nonce
        vm.prank(caller2);
        payable(caller2).transfer(0);

        address dep2 = _deploy(impl, address(0xA1), new bytes(0), caller2);
        assertEq(dep2, predicted, "caller 2 mismatch");
    }
}
