// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;



import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title Keep
/// @notice Core vault logic extracted from both Foundation and CharteredFund.
///         It stores the custody mapping plus helper (un)packing functions and
///         exposes internal primitives that derived contracts compose with
///         additional access-control and event emission.
abstract contract Keep {


    error Auth();
    error Math();
    error Fail();

    /*//////////////////////////////////////////////////////////////////////////
                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Packed balances: keccak256(user, token) => packed(userOwned, escrow)
    mapping(bytes32 => bytes32) public custody;

    /*//////////////////////////////////////////////////////////////////////////
                             PACK/UNPACK HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////////////////
                                UTILITIES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Best-effort check to distinguish ERC-721 / ERC-1155 tokens from fungible ERC-20s.
    ///
    /// 1. Attempt ERC-165 `supportsInterface` for the IERC721 interface id (0x80ac58cd) and the
    ///    IERC1155 interface id (0xd9b67a26).  A return value of `true` reliably identifies an NFT.
    /// 2. If the contract does not implement ERC-165 (or the call reverts), we fall back to the
    ///    old `decimals()` heuristic: well-behaved ERC-20s expose `decimals()`, while most NFTs do
    ///    not.  If `decimals()` is absent or the call reverts we assume the asset is an NFT.
    ///
    /// ETH (token == address(0)) is **not** considered an NFT.
    function _isNFT(address token) internal view returns (bool) {
        if (token == address(0)) return false;

        // --- 1️⃣  ERC-165 probe ----------------------------------------------------
        bytes4 ERC165_ID = 0x01ffc9a7; // supportsInterface(bytes4)
        bytes4 ERC721_ID = 0x80ac58cd;
        bytes4 ERC1155_ID = 0xd9b67a26;

        (bool ok721, bytes memory data721) = token.staticcall(abi.encodeWithSelector(ERC165_ID, ERC721_ID));
        if (ok721 && data721.length == 32 && abi.decode(data721, (bool))) {
            return true; // ERC-721 detected
        }

        (bool ok1155, bytes memory data1155) = token.staticcall(abi.encodeWithSelector(ERC165_ID, ERC1155_ID));
        if (ok1155 && data1155.length == 32 && abi.decode(data1155, (bool))) {
            return true; // ERC-1155 detected
        }

        // --- 2️⃣  Fallback to `decimals()` heuristic ------------------------------
        (bool okDec, bytes memory dataDec) = token.staticcall(abi.encodeWithSelector(0x313ce567)); // decimals()
        if (!okDec || dataDec.length == 0) {
            return true; // No decimals() => likely NFT
        }
        // Some contracts implement decimals() for NFTs returning 0. Treat 0 as NFT.
        uint8 dec = abi.decode(dataDec, (uint8));
        return dec == 0;
    }

    function _getCustodyKey(address user, address token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token));
    }

    function _splitAmount(bytes32 amount)
        internal
        pure
        returns (uint128 userOwned, uint128 escrow)
    {
        userOwned = uint128(uint256(amount));
        escrow    = uint128(uint256(amount >> 128));
    }

    function _packAmount(uint128 userOwned, uint128 escrow) internal pure returns (bytes32) {
        return bytes32(uint256(userOwned) | (uint256(escrow) << 128));
    }

    /*//////////////////////////////////////////////////////////////////////////
                              CORE OPERATIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Internal helper where `backend` transfers tokens on behalf of `user`.
    function _contributeFor(
        address sponsor,
        address user,
        address token,
        uint256 amount
    ) internal {
        bytes32 key = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        // sponsor must already have allowance.
        SafeTransferLib.safeTransferFrom(token, sponsor, address(this), amount);
        custody[key] = _packAmount(userOwned + uint128(amount), escrow);
    }

    /// @dev Move `amount` from protocol escrow (held under address(this)) to the
    ///      specified `user`'s escrow balance. Returns `true` if the transfer
    ///      succeeded (i.e. protocol escrow had enough), otherwise leaves state
    ///      untouched and returns `false`.
    function _allocate(address user, address token, uint256 amount) internal returns (bool) {
        bytes32 protocolKey = _getCustodyKey(address(this), token);
        (, uint128 protocolEscrow) = _splitAmount(custody[protocolKey]);
        if (protocolEscrow < amount) return false;

        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 userEscrow) = _splitAmount(custody[userKey]);

        // Update balances
        protocolEscrow -= uint128(amount);
        custody[protocolKey] = _packAmount(0, protocolEscrow);
        custody[userKey]    = _packAmount(userOwned, userEscrow + uint128(amount));
        return true;
    }

    /// @dev Adjust custody mapping for an ETH contribution.
    function _receiveETH(address from, uint256 value) internal {
        bytes32 key = _getCustodyKey(from, address(0));
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + uint128(value), escrow);
    }

    /// @dev Adjust custody mapping when an ERC-721 is transferred in.
    ///      `nft` is msg.sender (token contract), `from` is original owner.
    function _handleERC721(address nft, address from) internal {
        bytes32 key = _getCustodyKey(from, nft);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);
        custody[key] = _packAmount(userOwned + 1, escrow);
    }

    /// @dev Common donation logic. Caller must have already validated ETH value (if token == address(0)).
    function _donate(address payer, address token, uint256 amount, bool isNFT) internal {
        if (token == address(0)) {
            // ETH donation: amount already supplied as msg.value by payer.
            bytes32 key = _getCustodyKey(address(this), address(0));
            (uint128 owned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(owned + uint128(amount), escrow);
        } else if (isNFT) {
            // ERC721 tokenId == amount transferred from payer to this contract.
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(0x23b872dd, payer, address(this), amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "NFT transfer failed");
            bytes32 key = _getCustodyKey(address(this), token);
            (uint128 owned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(owned + 1, escrow);
        } else {
            // ERC20 donation
            SafeTransferLib.safeTransferFrom(token, payer, address(this), amount);
            bytes32 key = _getCustodyKey(address(this), token);
            (uint128 owned, uint128 escrow) = _splitAmount(custody[key]);
            custody[key] = _packAmount(owned + uint128(amount), escrow);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               RESCISSION HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    enum RescissionOutcome {
        UserOwnedWithdrawn,
        EscrowRefunded,
        Requested
    }

    /// @dev Core rescission logic shared by Foundation and CharteredFund.
    /// @param requester  The user asking to rescind.
    /// @param refundEnabled  Whether protocol-wide refund of escrow is allowed.
    /// @return outcome  Result of the operation.
    /// @return amount   Amount withdrawn (if any; 0 for Requested outcome).
    function _requestRescission(
        address requester,
        address token,
        bool refundEnabled
    ) internal returns (RescissionOutcome outcome, uint128 amount) {
        // Guard against NFTs which cannot be safely transferred via SafeTransferLib.
        if (_isNFT(token)) revert Fail();

        bytes32 key = _getCustodyKey(requester, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[key]);

        if (userOwned > 0) {
            // Allow immediate withdrawal of userOwned portion.
            if (token == address(0)) {
                SafeTransferLib.safeTransferETH(requester, userOwned);
            } else {
                SafeTransferLib.safeTransfer(token, requester, userOwned);
            }
            custody[key] = _packAmount(0, escrow);
            return (RescissionOutcome.UserOwnedWithdrawn, userOwned);
        }

        if (refundEnabled) {
            if (token == address(0)) {
                SafeTransferLib.safeTransferETH(requester, escrow);
            } else {
                SafeTransferLib.safeTransfer(token, requester, escrow);
            }
            custody[key] = _packAmount(userOwned, 0);
            return (RescissionOutcome.EscrowRefunded, escrow);
        }

        // Nothing withdrawn; just a request.
        return (RescissionOutcome.Requested, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 REMIT HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Handles balance adjustments for a remit operation.
    /// @param user  Recipient user whose escrow will be debited.
    /// @param fee   Protocol/charter fee portion to move into protocol escrow.
    /// @return success True if user had sufficient escrow, false otherwise.
    function _remit(
        address user,
        address token,
        uint256 amount,
        uint128 fee
    ) internal returns (bool success) {
        // Guard against NFTs which cannot be safely transferred via SafeTransferLib.
        if (_isNFT(token)) revert Fail();

        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[userKey]);
        uint256 total = amount + fee;
        if (escrow < total) return false;
        escrow -= uint128(total);
        custody[userKey] = _packAmount(userOwned, escrow);

        if (fee > 0) {
            bytes32 protocolKey = _getCustodyKey(address(this), token);
            (, uint128 protocolEscrow) = _splitAmount(custody[protocolKey]);
            custody[protocolKey] = _packAmount(0, protocolEscrow + fee);
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               COMMIT HELPER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Moves `escrowAmount` from userOwned to escrow for `user`.
    /// @return ok      True if operation succeeded (userOwned sufficient).
    /// @return ownedBefore  UserOwned balance before the move (for fee checks).
    function _commitEscrow(
        address user,
        address token,
        uint256 escrowAmount
    ) internal returns (bool ok, uint128 ownedBefore) {
        bytes32 userKey = _getCustodyKey(user, token);
        (uint128 userOwned, uint128 escrow) = _splitAmount(custody[userKey]);
        if (userOwned < escrowAmount) return (false, userOwned);
        custody[userKey] = _packAmount(userOwned - uint128(escrowAmount), escrow + uint128(escrowAmount));
        return (true, userOwned);
    }
}
