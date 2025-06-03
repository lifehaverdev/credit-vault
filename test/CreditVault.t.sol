// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {AiCreditVault} from "../src/implementation/CreditVault.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";

contract AiCreditVaultTest is Test {
    ERC1967Factory factory;
    AiCreditVault implementation;

    address admin = address(0xBEEF);
    address backend = address(0xFEED);
    address user = address(0xABCD);
    address USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Fake for test

    function setUp() public {
       
        factory = ERC1967Factory(0x0000000000006396FF2a80c067f99B3d2Ab4Df24);

        // Deploy the implementation once (not the proxy)
        implementation = new AiCreditVault();

        // Any addresses or static test prep
        // USDC and others can be declared at the top level if constant
    

    }

    function testMineVanityAddress() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        bytes memory initData = abi.encodeWithSelector(
            AiCreditVault.initialize.selector,
            tokens,
            backend
        );

        bytes32 salt;
        address predicted;
        uint96 counter;
        vm.pauseGasMetering();
        for (counter = 0; counter < type(uint96).max; counter++) {
            salt = bytes32(bytes.concat(bytes20(admin), bytes12(counter)));
            predicted = factory.predictDeterministicAddress(salt);
            if (uint160(predicted) >> 140 == 0x01152) {
                emit log_named_uint("Vanity Salt Found", counter);
                emit log_named_address("Vanity Address", predicted);
                break;
            }
        }
        vm.resumeGasMetering();
        require(uint160(predicted) >> 140 == 0x01152, "Failed to find vanity address");

        vm.prank(admin);
        address proxyAddress = factory.deployDeterministicAndCall(
            address(implementation),
            admin,
            salt,
            initData
        );

        assertEq(proxyAddress, predicted);
        AiCreditVault vault = AiCreditVault(payable(proxyAddress));
    }


    function testPredictAndDeploy() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        bytes memory initData = abi.encodeWithSelector(
            AiCreditVault.initialize.selector,
            tokens,
            backend
        );

        // Compute salt format: bytes32(admin || i)
        uint96 counter = 42; // Simulate found salt
        bytes32 salt = bytes32(bytes.concat(bytes20(admin), bytes12(counter)));

        // Predict address
        address predicted = factory.predictDeterministicAddress(salt);
        emit log_named_address("Predicted Proxy Address", predicted);

        // Deploy
        vm.prank(admin);
        address proxyAddress = factory.deployDeterministicAndCall(
            address(implementation),
            admin,
            salt,
            initData
        );

        assertEq(proxyAddress, predicted, "Proxy address mismatch");

        // Bind interface to proxy
        AiCreditVault vault = AiCreditVault(payable(proxyAddress));

    }

    // Debt 

}
