// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Foundation} from "../src/Foundation.sol";
import {CharteredFundImplementation} from "../src/CharteredFundImplementation.sol";
import {CharteredFundImplementationV2} from "./mocks/CharteredFundImplementationV2.sol";
import {UpgradeableBeacon} from "solady/utils/UpgradeableBeacon.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {VanitySalt} from "./utils/VanitySalt.sol";

interface IERC721 {
    function ownerOf(uint256) external view returns (address);
}

contract BeaconUpgradeTest is Test {
    Foundation root;
    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;

    // MiladyStation NFT used to gate owner functions
    address ownerNFT;
    uint256 ownerTokenId;

    address charterBeacon;

    function setUp() public {
        uint256 mainnetFork = vm.createSelectFork(vm.rpcUrl("mainnet"));

        backend = makeAddr("backend");
        user = makeAddr("user");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user, 10 ether);

        // Pick chain-appropriate NFT for owner check.
        (ownerNFT, ownerTokenId) = _selectOwnerNFT();

        // Deploy CharteredFund implementation and beacon
        address cfImpl = address(new CharteredFundImplementation());
        charterBeacon = address(new UpgradeableBeacon(admin, cfImpl));
        address beacon = charterBeacon;

        // Deploy Foundation proxy via factory
        address proxy = new ERC1967Factory().deploy(address(new Foundation()), admin);
        root = Foundation(payable(proxy));

        // Initialize with beacon
        vm.prank(admin);
        root.initialize(ownerNFT, ownerTokenId, beacon);

        // Transfer beacon ownership to the root so upgrade tests pass.
        vm.prank(admin);
        UpgradeableBeacon(beacon).transferOwnership(address(root));

        // Authorize backend marshal
        vm.prank(admin);
        root.setMarshal(backend, true);

        // Ensure NFT owner is admin on fork (may not be). If not, skip owner checks.
    }

    function test_charterFund_throughBeacon() public {
        bytes memory args = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            address(root),
            user
        );
        bytes32 salt = VanitySalt.mine(charterBeacon, args, address(root), 1_000_000);

        address predicted = root.computeCharterAddress(user, salt);

        vm.startPrank(backend);
        vm.expectEmit(true, true, true, true, address(root));
        emit Foundation.FundChartered(predicted, user, salt);
        address fundAddress = root.charterFund(user, salt);
        vm.stopPrank();

        assertEq(fundAddress, predicted, "Address mismatch");
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(fundAddress)
        }
        assertTrue(codeSize > 0, "Proxy code not deployed");
    }

    function test_upgradePropagation() public {
        // Charter fund first
        bytes memory args2 = abi.encodeWithSelector(
            CharteredFundImplementation.initialize.selector,
            address(root),
            user
        );
        bytes32 salt = VanitySalt.mine(charterBeacon, args2, address(root), 1_000_000);

        // Deploy the fund via backend marshal
        vm.prank(backend);
        address fundAddress = root.charterFund(user, salt);

        // Confirm version() is not available yet
        (, bytes memory revertData) = fundAddress.staticcall(abi.encodeWithSignature("version()"));
        assertEq(revertData.length, 0, "version should revert in V1");

        // Deploy V2 impl and upgrade beacon via admin
        address newImpl = address(new CharteredFundImplementationV2());
        vm.prank(admin);
        root.upgradeCharterImplementation(newImpl);

        // After upgrade, version() should return 2
        uint256 ver = CharteredFundImplementationV2(payable(fundAddress)).version();
        assertEq(ver, 2);
    }

    function _selectOwnerNFT() internal returns (address nft, uint256 tokenId) {
        address milady = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
        uint256 id = 598;
        (bool ok, bytes memory data) = milady.staticcall(abi.encodeWithSelector(0x6352211e, id));
        if (ok && data.length == 32 && abi.decode(data, (address)) == admin) {
            return (milady, id);
        }
        // Otherwise deploy mock NFT & mint to admin.
        MockERC721 mock = new MockERC721();
        mock.mint(admin, 1);
        return (address(mock), 1);
    }
}
