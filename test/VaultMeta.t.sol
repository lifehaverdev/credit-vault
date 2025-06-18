// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {VaultRoot} from "../src/VaultRoot.sol";
import {VaultRootV2} from "./mocks/VaultRootV2.sol";
import {VaultAccount} from "../src/VaultAccount.sol";
import {ERC1967Factory} from "solady/utils/ERC1967Factory.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract VaultMetaTest is Test {
    VaultRoot root;
    address proxyAddress;

    address admin = 0x1821BD18CBdD267CE4e389f893dDFe7BEB333aB6;
    address backend;
    address user;
    address anotherUser;
    
    address private constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;
    address internal pepeWhale = 0x4a2C786651229175407d3A2D405d1998bcf40614;

    address private constant MILADYSTATION = 0xB24BaB1732D34cAD0A7C7035C3539aEC553bF3a0;
    address private constant MSWhale = 0x65ccFF5cFc0E080CdD4bb29BC66A3F71153382a2;

    event DepositRecorded(address indexed vaultAccount, address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        backend = makeAddr("backend");
        user = makeAddr("user");
        anotherUser = makeAddr("anotherUser");

        vm.deal(admin, 10 ether);
        vm.deal(backend, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(anotherUser, 10 ether);
        vm.deal(pepeWhale, 10 ether);
        
        address impl = address(new VaultRoot());
        proxyAddress = new ERC1967Factory().deploy(
            impl,
            admin
        );
        root = VaultRoot(payable(proxyAddress));
        
        vm.prank(admin);
        root.initialize();

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
        // 1. Make deposits to V1
        uint256 ethDepositAmount = 1 ether;
        uint256 erc20DepositAmount = 1_000_000 * 1e18;

        vm.prank(user);
        (bool success, ) = proxyAddress.call{value: ethDepositAmount}("");
        require(success);

        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(proxyAddress, erc20DepositAmount);
        root.deposit(PEPE, erc20DepositAmount);
        vm.stopPrank();

        bytes32 ethKey = _getCustodyKey(user, address(0));
        (uint128 userOwnedEth, ) = _splitAmount(root.custody(ethKey));
        assertEq(userOwnedEth, ethDepositAmount);

        bytes32 pepeKey = _getCustodyKey(pepeWhale, PEPE);
        (uint128 userOwnedPepe, ) = _splitAmount(root.custody(pepeKey));
        assertEq(userOwnedPepe, erc20DepositAmount);
        
        // 2. Deploy V2 and upgrade
        VaultRootV2 v2Impl = new VaultRootV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));

        VaultRootV2 v2Proxy = VaultRootV2(payable(proxyAddress));

        // 3. Assert state is preserved
        (userOwnedEth, ) = _splitAmount(v2Proxy.custody(ethKey));
        assertEq(userOwnedEth, ethDepositAmount, "ETH custody should be preserved");

        (userOwnedPepe, ) = _splitAmount(v2Proxy.custody(pepeKey));
        assertEq(userOwnedPepe, erc20DepositAmount, "ERC20 custody should be preserved");

        assertEq(v2Proxy.version(), "V2");
        
        uint256 userEthBalanceBefore = user.balance;
        vm.prank(user);
        v2Proxy.withdraw(address(0));
        assertTrue(user.balance > userEthBalanceBefore);

        uint256 whalePepeBalanceBefore = ERC20(PEPE).balanceOf(pepeWhale);
        vm.prank(pepeWhale);
        v2Proxy.withdraw(PEPE);
        assertEq(ERC20(PEPE).balanceOf(pepeWhale), whalePepeBalanceBefore + erc20DepositAmount);
    }

    function test_upgrade_preservesEventsAndAccess() public {
        VaultRootV2 v2Impl = new VaultRootV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));
        VaultRootV2 v2Proxy = VaultRootV2(payable(proxyAddress));

        vm.prank(user);
        vm.expectRevert("Not backend");
        v2Proxy.createVaultAccount(user, "salt");

        vm.prank(user);
        vm.expectRevert("Not the owner of the token");
        v2Proxy.setFreeze(false);

        uint256 depositAmount = 1 ether;
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit DepositRecorded(proxyAddress, user, address(0), depositAmount);
        (bool success, ) = proxyAddress.call{value: depositAmount}("");
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

        VaultRootV2 v2Impl = new VaultRootV2();
        vm.prank(admin);
        root.upgradeToAndCall(address(v2Impl), bytes(""));
        VaultRootV2 v2Proxy = VaultRootV2(payable(proxyAddress));
        
        (uint128 userOwnedNftAfter, ) = _splitAmount(v2Proxy.custody(nftKey));
        assertEq(userOwnedNftAfter, 1, "NFT custody should be preserved");

        vm.expectRevert();
        vm.prank(MSWhale);
        v2Proxy.withdraw(MILADYSTATION);
    }

    // --- ⛽ Gas Benchmarking Tests ---

    function testGas_root_vs_account_deposit_eth() public {
        console.log("");
        console.log("--- Deposit Gas ---");
        vm.prank(backend);
        address accountAddress = root.createVaultAccount(user, "salt");
        
        // Root deposit
        uint256 gasStart_root = gasleft();
        vm.prank(user);
        (bool s1, ) = proxyAddress.call{value: 1 ether}("");
        require(s1);
        uint256 gasUsed_root = gasStart_root - gasleft();
        console.log("VaultRoot ETH deposit:", gasUsed_root);

        // Account deposit
        uint256 gasStart_account = gasleft();
        vm.prank(user);
        (bool s2, ) = accountAddress.call{value: 1 ether}(new bytes(0));
        require(s2);
        uint256 gasUsed_account = gasStart_account - gasleft();
        console.log("VaultAccount ETH deposit:", gasUsed_account);
    }

    function testGas_blessEscrow_vs_confirmCredit() public {
        console.log("");
        console.log("--- Credit Method Gas ---");
        uint256 amount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: amount * 2}("");
        require(s);

        bytes32 protocolKey = _getCustodyKey(address(root), address(0));
        vm.store(address(root), keccak256(abi.encode(protocolKey, 0)), _packAmount(0, uint128(amount)));

        // blessEscrow
        uint256 gasStart_bless = gasleft();
        vm.prank(backend);
        root.blessEscrow(anotherUser, address(0), amount);
        uint256 gasUsed_bless = gasStart_bless - gasleft();
        console.log("blessEscrow:", gasUsed_bless);

        // confirmCredit
        uint256 gasStart_confirm = gasleft();
        vm.prank(backend);
        root.confirmCredit(address(root), user, address(0), amount, 0, "");
        uint256 gasUsed_confirm = gasStart_confirm - gasleft();
        console.log("confirmCredit:", gasUsed_confirm);
    }

    function testGas_userWithdraw_eth_vs_erc20_vs_nft() public {
        console.log("");
        console.log("--- User Withdraw Gas ---");
        // ETH
        uint256 ethAmount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: ethAmount}("");
        require(s);

        // ERC20
        uint256 pepeAmount = 1_000_000e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), pepeAmount);
        root.deposit(PEPE, pepeAmount);
        vm.stopPrank();

        // NFT
        uint256[] memory tokenIds = IERC721(MILADYSTATION).tokensOfOwner(MSWhale);
        require(tokenIds.length > 0, "MSWhale needs a Milady");
        uint256 tokenId = tokenIds[0];
        vm.startPrank(MSWhale);
        IERC721(MILADYSTATION).approve(proxyAddress, tokenId);
        IERC721(MILADYSTATION).safeTransferFrom(MSWhale, proxyAddress, tokenId);
        vm.stopPrank();

        uint256 gasStart_eth_withdraw = gasleft();
        vm.prank(user);
        root.withdraw(address(0));
        uint256 gasUsed_eth_withdraw = gasStart_eth_withdraw - gasleft();
        console.log("User withdraw ETH:", gasUsed_eth_withdraw);

        uint256 gasStart_erc20_withdraw = gasleft();
        vm.prank(pepeWhale);
        root.withdraw(PEPE);
        uint256 gasUsed_erc20_withdraw = gasStart_erc20_withdraw - gasleft();
        console.log("User withdraw ERC20:", gasUsed_erc20_withdraw);

        // NFT withdraw is expected to fail.
        vm.expectRevert();
        uint256 gasStart_nft_withdraw = gasleft();
        vm.prank(MSWhale);
        root.withdraw(MILADYSTATION);
        uint256 gasUsed_nft_withdraw = gasStart_nft_withdraw - gasleft();
        console.log("User withdraw NFT (revert expected):", gasUsed_nft_withdraw);
    }

    function testGas_backendWithdrawTo_eth_vs_erc20() public {
        console.log("");
        console.log("--- Backend WithdrawTo Gas ---");
        uint256 ethAmount = 1 ether;
        vm.prank(user);
        (bool s, ) = proxyAddress.call{value: ethAmount}("");
        require(s);
        vm.prank(backend);
        root.confirmCredit(address(root), user, address(0), ethAmount, 0, "");

        uint256 pepeAmount = 1_000_000e18;
        vm.startPrank(pepeWhale);
        ERC20(PEPE).approve(address(root), pepeAmount);
        root.deposit(PEPE, pepeAmount);
        vm.stopPrank();
        vm.prank(backend);
        root.confirmCredit(address(root), pepeWhale, PEPE, pepeAmount, 0, "");

        uint256 gasStart_eth_backend_withdraw = gasleft();
        vm.prank(backend);
        root.withdrawTo(user, address(0), ethAmount, 0, "");
        uint256 gasUsed_eth_backend_withdraw = gasStart_eth_backend_withdraw - gasleft();
        console.log("Backend withdrawTo ETH:", gasUsed_eth_backend_withdraw);

        uint256 gasStart_erc20_backend_withdraw = gasleft();
        vm.prank(backend);
        root.withdrawTo(pepeWhale, PEPE, pepeAmount, 0, "");
        uint256 gasUsed_erc20_backend_withdraw = gasStart_erc20_backend_withdraw - gasleft();
        console.log("Backend withdrawTo ERC20:", gasUsed_erc20_backend_withdraw);
    }
} 