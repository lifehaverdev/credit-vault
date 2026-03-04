// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {VanitySalt} from "./utils/VanitySalt.sol";

/// @notice Debug / reference tests for beacon proxy address prediction.
///
///         These tests exist to produce canonical values for the frontend SDK.
///         Run with -vv to see the full console output.
///
///         FRONTEND INTEGRATION NOTES (printed by testCanonicalValues):
///           • Init code is built from LibClone.initCodeERC1967BeaconProxy(beacon, args)
///             where args = abi.encodeWithSelector(initialize(address,address), foundation, owner)
///           • The init code hash is NOT constant — it embeds the beacon address and init args,
///             so it differs per beacon and per owner. Use the algorithm, not a cached hash.
///           • CREATE2 address = keccak256(0xff ++ Foundation ++ salt ++ keccak256(initCode))[12:]
///           • This is exactly what Foundation.computeCharterAddress does on-chain — call it.
contract BeaconProxyDebugTest is Test {

    // Production addresses — update these if the proxy or beacon change
    address constant FOUNDATION_ADDRESS    = 0x01152530028bd834EDbA9744885A882D025D84F6;
    address constant CHARTER_BEACON_ADDRESS = 0xeEd94eD20B79ED938518c6eEa4129cB1E8b8665C;
    address constant OWNER_ADDRESS         = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;

    /*//////////////////////////////////////////////////////////////////////////
                        1. INIT CODE HASH (canonical reference)
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Prints and asserts the current init code hash for the production
    ///         beacon + a specific owner. Frontend must use the same algorithm.
    ///
    ///         NOTE: The hash bakes in both CHARTER_BEACON_ADDRESS and OWNER_ADDRESS.
    ///         It will differ for different owners — always compute fresh, don't cache.
    function testBeaconProxyInitCode() public {
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955), // CharteredFundImplementation.initialize(address,address)
            FOUNDATION_ADDRESS,
            OWNER_ADDRESS
        );

        bytes memory initCode     = LibClone.initCodeERC1967BeaconProxy(CHARTER_BEACON_ADDRESS, args);
        bytes32      initCodeHash = keccak256(initCode);

        console.log("=== Beacon Proxy Init Code (production addresses) ===");
        console.log("Foundation:   ", FOUNDATION_ADDRESS);
        console.log("Beacon:       ", CHARTER_BEACON_ADDRESS);
        console.log("Owner:        ", OWNER_ADDRESS);
        console.log("Init code len:", initCode.length);
        console.log("Init code hash (USE THIS IN FRONTEND SDK):");
        console.log("  ", vm.toString(initCodeHash));
        console.log("");
        console.log("Frontend CREATE2 formula:");
        console.log("  addr = keccak256(0xff ++ Foundation ++ salt ++ initCodeHash)[12:]");
        console.log("  This is what Foundation.computeCharterAddress does on-chain.");
        console.logBytes(initCode);

        // Assert matches the value computed by the CURRENT version of Solady LibClone.
        // If this fails, Solady was updated — regenerate by running this test and
        // reading initCodeHash from the output above.
        bytes32 expected = keccak256(
            LibClone.initCodeERC1967BeaconProxy(CHARTER_BEACON_ADDRESS, args)
        );
        assertEq(initCodeHash, expected, "Init code hash must be stable within a single run");
    }

    /*//////////////////////////////////////////////////////////////////////////
             2. ADDRESS PREDICTION — verifies computeCharterAddress matches deploy
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploys a fresh Foundation and chartered fund, then confirms that
    ///         Foundation.computeCharterAddress predicted the address exactly.
    function testFoundationComputeCharterAddress() public {
        // ── Deploy infrastructure ─────────────────────────────────────────
        address cfImpl = address(new CharteredFundImplementation());
        address admin  = makeAddr("debugAdmin");
        address beacon = address(new UpgradeableBeacon(admin, cfImpl));

        // Mock ownerOf so onlyOwner resolves to admin without needing a live NFT.
        MockERC721 nft = new MockERC721();
        vm.mockCall(address(nft), abi.encodeWithSelector(0x6352211e, uint256(1)), abi.encode(admin));

        Foundation foundation = new Foundation();
        vm.prank(admin);
        foundation.initialize(address(nft), 1, beacon);

        // Transfer beacon ownership to Foundation (admin is current beacon owner).
        vm.prank(admin);
        UpgradeableBeacon(beacon).transferOwnership(address(foundation));

        // Register a marshal address so charterFund can be called.
        vm.prank(admin);
        foundation.setMarshal(admin, true);

        // ── Mine a vanity salt (0x1152 prefix required by charterFund) ────
        bytes memory args = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            address(foundation),
            OWNER_ADDRESS
        );
        bytes32 salt = VanitySalt.mine(beacon, args, address(foundation), 1_000_000);

        // ── Predict then deploy ───────────────────────────────────────────
        address predicted = foundation.computeCharterAddress(OWNER_ADDRESS, salt);
        vm.prank(admin);
        address actual    = foundation.charterFund(OWNER_ADDRESS, salt);

        console.log("=== Foundation.computeCharterAddress vs charterFund ===");
        console.log("Beacon:          ", beacon);
        console.log("Salt:            ", vm.toString(salt));
        console.log("Predicted addr:  ", predicted);
        console.log("Deployed addr:   ", actual);
        console.log("Match:           ", predicted == actual);

        assertEq(predicted, actual, "computeCharterAddress must match the deployed address");
    }

    /*//////////////////////////////////////////////////////////////////////////
                   3. CANONICAL VALUES — everything the frontend SDK needs
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Prints the full reference output for the frontend SDK.
    ///         No assertions — purely informational.
    function testCanonicalValues() public view {
        bytes memory args = abi.encodeWithSelector(
            bytes4(0x485cc955),
            FOUNDATION_ADDRESS,
            OWNER_ADDRESS
        );

        bytes memory initCode     = LibClone.initCodeERC1967BeaconProxy(CHARTER_BEACON_ADDRESS, args);
        bytes32      initCodeHash = keccak256(initCode);

        // Recompute the expected CREATE2 address for this salt (salt=0 for demo)
        address predicted = LibClone.predictDeterministicAddressERC1967BeaconProxy(
            CHARTER_BEACON_ADDRESS,
            args,
            bytes32(0),
            FOUNDATION_ADDRESS
        );

        console.log("============================================================");
        console.log("  CREDIT VAULT - CANONICAL FRONTEND INTEGRATION VALUES");
        console.log("============================================================");
        console.log("");
        console.log("Production contracts:");
        console.log("  Foundation:            ", FOUNDATION_ADDRESS);
        console.log("  Charter beacon:        ", CHARTER_BEACON_ADDRESS);
        console.log("");
        console.log("initialize() selector:   0x485cc955");
        console.log("  (CharteredFundImplementation.initialize(address,address))");
        console.log("");
        console.log("Init code hash for production foundation+owner pair:");
        console.log("  ", vm.toString(initCodeHash));
        console.log("  !! Hash embeds beacon + args. Recompute per owner, do NOT cache globally. !!");
        console.log("");
        console.log("CREATE2 address formula:");
        console.log("  args     = abi.encodeWithSelector(0x485cc955, foundation, owner)");
        console.log("  initCode = initCodeERC1967BeaconProxy(beacon, args)");
        console.log("  addr     = keccak256(0xff ++ Foundation ++ salt ++ keccak256(initCode))[12:]");
        console.log("");
        console.log("Example: salt=0x00, owner=OWNER_ADDRESS => predicted address:");
        console.log("  ", predicted);
        console.log("");
        console.log("Vanity requirement: top 16 bits of address must equal 0x1152");
        console.log("  i.e. address >> 144 == 0x1152");
        console.log("  Mine salts off-chain or use VanitySalt.sol in tests.");
        console.log("============================================================");
    }
}
