// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Foundation} from "src/Foundation.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {ERC1967Proxy} from "createx-forge/src/ERC1967Proxy.sol";

interface IImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes memory initCode) external payable returns (address);
}

/// @notice Unit-tests that our deterministic inputs generate the **same**
///         implementation & proxy addresses on both Sepolia and Mainnet forks.
///         Replace the constants below with the real values you mined.
contract DeterministicAddressTest is Test {
    // ---------------------------------------------------------------------
    // CONSTANTS — UPDATE BEFORE RUNNING
    // ---------------------------------------------------------------------
    address constant IMPL_DEPLOYER = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6; // virgin wallet (nonce-0)
    bytes32 constant IMPL_SALT     = bytes32(uint256(21245));                    // vanity salt for implementation

    address constant FACTORY       = 0x0000000000FFe8B47B3e2130213B802212439497; // ImmutableCreate2Factory
    bytes32 constant PROXY_SALT    = bytes32(uint256(998877));                   // vanity salt for proxy
    address constant PROXY_ADMIN   = 0x1152115211521152115211521152115211521152; // proxy admin (constant)
    address constant CALLER_WALLET = 0x1111222233334444555566667777888899990000; // broadcasts proxy deployment
    // ---------------------------------------------------------------------

    function _predictImpl() internal view returns (address) {
        return CREATE3.predictDeterministicAddress(IMPL_SALT, IMPL_DEPLOYER);
    }

    function _proxyInitCode(address implementation) internal pure returns (bytes memory) {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, PROXY_ADMIN));
    }

    function _predictProxy(address implementation) internal pure returns (address) {
        bytes32 initHash = keccak256(_proxyInitCode(implementation));
        return address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), FACTORY, PROXY_SALT, initHash)
        ))));
    }

    /// @notice Checks predictions on the current fork.
    function test_LocalPredictions() public {
        address impl  = _predictImpl();
        address proxy = _predictProxy(impl);
        emit log_named_address("Predicted implementation", impl);
        emit log_named_address("Predicted proxy", proxy);
        assertEq(uint160(proxy) >> 140, uint160(impl) >> 140, "vanity upper-nibble mismatch");
    }

    /// @notice Ensures predictions are identical on Sepolia & Mainnet forks.
    ///         Requires `[rpc_endpoints]` for `sepolia` and `mainnet` in foundry.toml.
    function test_DeterminismAcrossChains() external {
        uint256 sepoliaFork = vm.createFork(vm.rpcUrl("sepolia"));
        uint256 mainFork    = vm.createFork(vm.rpcUrl("mainnet"));

        // Sepolia predictions
        vm.selectFork(sepoliaFork);
        address implSepolia  = _predictImpl();
        address proxySepolia = _predictProxy(implSepolia);

        // Mainnet predictions
        vm.selectFork(mainFork);
        address implMainnet  = _predictImpl();
        address proxyMainnet = _predictProxy(implMainnet);

        assertEq(implSepolia, implMainnet,   "implementation mismatch");
        assertEq(proxySepolia, proxyMainnet, "proxy mismatch");
    }

    /// @notice End-to-end deploy on a fork: deploy implementation via CREATE3,
    ///         then proxy via ImmutableCreate2Factory, and assert addresses.
    function _deployAndAssert() internal {
        // --- Fund wallets with 10 ether each ---
        vm.deal(IMPL_DEPLOYER, 10 ether);
        vm.deal(CALLER_WALLET, 10 ether);

        // --- Deploy Implementation via CREATE3 ---
        vm.startPrank(IMPL_DEPLOYER);
        address impl = CREATE3.deployDeterministic(type(Foundation).creationCode, IMPL_SALT);
        vm.stopPrank();
        assertEq(impl, _predictImpl(), "implementation deployment mismatch");

        // --- Deploy Proxy via factory ---
        bytes memory proxyInit = _proxyInitCode(impl);
        vm.startPrank(CALLER_WALLET);
        address proxy = IImmutableCreate2Factory(FACTORY).safeCreate2(PROXY_SALT, proxyInit);
        vm.stopPrank();
        assertEq(proxy, _predictProxy(impl), "proxy deployment mismatch");
    }

    function test_EndToEnd_SepoliaFork() external {
        uint256 forkId = vm.createFork(vm.rpcUrl("sepolia"));
        vm.selectFork(forkId);
        _deployAndAssert();
    }

    function test_EndToEnd_MainnetFork() external {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"));
        vm.selectFork(forkId);
        _deployAndAssert();
    }
}
