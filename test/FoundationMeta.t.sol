// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Foundation} from "../src/Foundation.sol";
import {FoundationV2} from "./mocks/FoundationV2.sol";
import {CharteredFund} from "../src/CharteredFund.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {IFoundation} from "../src/interfaces/IFoundation.sol";

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract FoundationMetaTest is Test {
    Foundation root;
    address proxyAddress;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;
    address anotherUser;
    
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address internal pepeWhale = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    address private constant MILADYSTATION = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
    address private constant MSWhale = 0x65ccFF5cFc0E080CdD4bb29BC66A3F71153382a2;

    event ContributionRecorded(address indexed fundAddress, address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        backend = makeAddr("backend");
        user = makeAddr("user");
        anotherUser = makeAddr("anotherUser");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(anotherUser, 10 ether);
        vm.deal(pepeWhale, 10 ether);
        
        address impl = address(new Foundation());
        proxyAddress = new ERC1967Factory().deploy(
            impl,
            admin
        );
        root = Foundation(payable(proxyAddress));
        
        vm.prank(admin);
        root.initialize(MILADYSTATION, 598);

        vm.prank(admin);
        root.setBackend(backend, true);

        vm.prank(admin);
        root.setFreeze(true);
    }
    
    function _getCustodyKey(address _user, address _token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _token));
    }

    function _splitAmount(bytes32 amount) internal pure returns(uint128 userOwned, uint128 escrow) {
        userOwned = uint128(uint256(amount));
        escrow = uint128(uint256(amount >> 128));
    }

    function _packAmount(uint128 userOwned, uint128 escrow) internal pure returns(bytes32) {
        return bytes32(uint256(userOwned) | (uint256(escrow) << 128));
    }

    // --- 🔄 Upgradeability Tests ---

    function test_upgrade_doesNotAffectCustodyState() public {
        // 1. Make contributes to V1
        uint256 ethContributeAmount = 1 ether;
        uint256 erc20ContributeAmount = 1_000_000 * 1e18;

        vm.prank(user);
        (bool success, ) = proxyAddress.call{value: ethContributeAmount}("");
        require(success);

        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(proxyAddress, erc20ContributeAmount);
        root.contribute(PEPE, erc20ContributeAmount);
        vm.stopPrank();

        bytes32 ethKey = _getCustodyKey(user, address(0));
        (uint128 userOwnedEth, ) = _splitAmount(root.custody(ethKey));
        assertEq(userOwnedEth, ethContributeAmount);

        bytes32 pepeKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwnedPepe, ) = _splitAmount(root.custody(pepeKey));
        assertEq(userOwnedPepe, erc20ContributeAmount);
        
        // 2. Deploy V2 and upgrade
        FoundationV2 v2Impl = new FoundationV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));

        FoundationV2 v2Proxy = FoundationV2(payable(proxyAddress));

        // 3. Assert state is preserved
        (userOwnedEth, ) = _splitAmount(v2Proxy.custody(ethKey));
        assertEq(userOwnedEth, ethContributeAmount, "ETH custody should be preserved");

        (userOwnedPepe, ) = _splitAmount(v2Proxy.custody(pepeKey));
        assertEq(userOwnedPepe, erc20ContributeAmount, "ERC20 custody should be preserved");

        assertEq(v2Proxy.version(), "V2");
        
        uint256 userEthBalanceBefore = user.balance;
        vm.prank(user);
        v2Proxy.requestRescission(address(0));
        assertTrue(user.balance > userEthBalanceBefore);

        uint256 whalePepeBalanceBefore = ERC20(PEPE).balanceOf(pepeWhale);
        vm.prank(pepeWhale);
        v2Proxy.requestRescission(PEPE);
        assertEq(ERC20(PEPE).balanceOf(pepeWhale), whalePepeBalanceBefore + erc20ContributeAmount);
    }

    function test_upgrade_preservesEventsAndAccess() public {
        FoundationV2 v2Impl = new FoundationV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));
        FoundationV2 v2Proxy = FoundationV2(payable(proxyAddress));

        vm.prank(user);
        vm.expectRevert(IFoundation.NotBackend.selector);
        v2Proxy.charterFund(user, "salt");

        vm.prank(user);
        vm.expectRevert(IFoundation.NotOwner.selector);
        v2Proxy.setFreeze(false);

        uint256 contributeAmount = 1 ether;
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit ContributionRecorded(proxyAddress, user, address(0), contributeAmount);
        (bool success, ) = proxyAddress.call{value: contributeAmount}("");
        require(success);
    }

    function test_upgrade_doesNotAffectNFTCustody() public {
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale needs a Milady");
        uint256 tokenId = tokenIds[0];

        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).approve(proxyAddress, tokenId);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, proxyAddress, tokenId);
        vm.stopPrank();

        bytes32 nftKey = _getCustodyKey(MSWhale, MILADYSTATION);
        (uint128 userOwnedNft, ) = _splitAmount(root.custody(nftKey));
        assertEq(userOwnedNft, 1);

        FoundationV2 v2Impl = new FoundationV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));
        FoundationV2 v2Proxy = FoundationV2(payable(proxyAddress));
        
        (uint128 userOwnedNftAfter, ) = _splitAmount(v2Proxy.custody(nftKey));
        assertEq(userOwnedNftAfter, 1, "NFT custody should be preserved");

        vm.expectRevert();
        vm.prank(MSWhale);
        v2Proxy.requestRescission(MILADYSTATION);
    }

    // --- ⛽ Gas Benchmarking Tests ---

    function testGas_root_vs_fund_contribute_eth() public {
        console.log("");
        console.log("--- Contribute Gas ---");
        vm.prank(backend);
        address fundAddress = root.charterFund(user, "salt");
        
        // Root contribute
        uint256 gasStart_root = gasleft();
        vm.prank(user);
        (bool s1, ) = proxyAddress.call{value: 1 ether}("");
        require(s1);
        uint256 gasUsed_root = gasStart_root - gasleft();
        console.log("Foundation ETH contribute:", gasUsed_root);

        // Fund contribute
        uint256 gasStart_fund = gasleft();
        vm.prank(user);
        (bool s2, ) = fundAddress.call{value: 1 ether}(new bytes(0));
        require(s2);
        uint256 gasUsed_fund = gasStart_fund - gasleft();
        console.log("CharteredFund ETH contribute:", gasUsed_fund);
    }

    function testGas_allocate_vs_commit() public {
        console.log("");
        console.log("--- Credit Method Gas ---");
        uint256 amount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: amount * 2}("");
        require(s);

        bytes32 protocolKey = _getCustodyKey(address(root), address(0));
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), _packAmount(0, uint128(amount)));

        // allocate
        uint256 gasStart_allocate = gasleft();
        vm.prank(backend);
        root.allocate(anotherUser, address(0), amount);
        uint256 gasUsed_allocate = gasStart_allocate - gasleft();
        console.log("allocate:", gasUsed_allocate);

        // commit
        uint256 gasStart_commit = gasleft();
        vm.prank(backend);
        root.commit(address(root), user, address(0), amount, 0, "");
        uint256 gasUsed_commit = gasStart_commit - gasleft();
        console.log("commit:", gasUsed_commit);
    }

    function testGas_userRequestRescission_eth_vs_erc20_vs_nft() public {
        console.log("");
        console.log("--- User Rescind Gas ---");
        // ETH
        uint256 ethAmount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: ethAmount}("");
        require(s);

        // ERC20
        uint256 pepeAmount = 1_000_000e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), pepeAmount);
        root.contribute(PEPE, pepeAmount);
        vm.stopPrank();

        // NFT
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale needs a Milady");
        uint256 tokenId = tokenIds[0];
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).approve(proxyAddress, tokenId);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, proxyAddress, tokenId);
        vm.stopPrank();

        uint256 gasStart_eth_rescind = gasleft();
        vm.prank(user);
        root.requestRescission(address(0));
        uint256 gasUsed_eth_rescind = gasStart_eth_rescind - gasleft();
        console.log("User rescind ETH:", gasUsed_eth_rescind);

        uint256 gasStart_erc20_rescind = gasleft();
        vm.prank(pepeWhale);
        root.requestRescission(PEPE);
        uint256 gasUsed_erc20_rescind = gasStart_erc20_rescind - gasleft();
        console.log("User rescind ERC20:", gasUsed_erc20_rescind);

        // NFT rescind is expected to fail.
        vm.expectRevert();
        uint256 gasStart_nft_rescind = gasleft();
        vm.prank(MSWhale);
        root.requestRescission(MILADYSTATION);
        uint256 gasUsed_nft_rescind = gasStart_nft_rescind - gasleft();
        console.log("User rescind NFT (revert expected):", gasUsed_nft_rescind);
    }

    function testGas_backendRemit_eth_vs_erc20() public {
        console.log("");
        console.log("--- Backend Remit Gas ---");
        uint256 ethAmount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: ethAmount}("");
        require(s);
        vm.prank(backend);
        root.commit(address(root), user, address(0), ethAmount, 0, "");

        uint256 pepeAmount = 1_000_000e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), pepeAmount);
        root.contribute(PEPE, pepeAmount);
        vm.stopPrank();
        vm.prank(backend);
        root.commit(address(root), pepeWhale, PEPE, pepeAmount, 0, "");

        uint256 gasStart_eth_backend_remit = gasleft();
        vm.prank(backend);
        root.remit(user, address(0), ethAmount, 0, "");
        uint256 gasUsed_eth_backend_remit = gasStart_eth_backend_remit - gasleft();
        console.log("Backend remit ETH:", gasUsed_eth_backend_remit);

        uint256 gasStart_erc20_backend_remit = gasleft();
        vm.prank(backend);
        root.remit(pepeWhale, PEPE, pepeAmount, 0, "");
        uint256 gasUsed_erc20_backend_remit = gasStart_erc20_backend_remit - gasleft();
        console.log("Backend remit ERC20:", gasUsed_erc20_backend_remit);
    }

    /*
    test_canInitializeAndSetBackend()	✔ Initialization & state
    test_initializeIsProtected()	✔ Cannot re-init
    test_canUpgradeAndCallNewLogic()	✔ Upgrade path works
    test_onlyAdminCanUpgrade()	✔ Admin-only enforcement
    test_upgradeToInvalidImplementationFails()	✔ UUPS compliance check
    */
} 