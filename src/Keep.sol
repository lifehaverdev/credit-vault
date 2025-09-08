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

    /// @dev Heuristic check for ERC-721 vs ERC-20. We attempt to call `decimals()` which
    ///      is expected to exist on well-behaved ERC-20 contracts. If the call reverts or
    ///      returns no data, we assume the asset is an NFT (or otherwise incompatible
    ///      with `SafeTransferLib.safeTransfer` semantics).
    ///      ETH (token == address(0)) is **not** considered an NFT.
    function _isNFT(address token) internal view returns (bool) {
        if (token == address(0)) return false;
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x313ce567)); // decimals()
        return !ok || data.length == 0;
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
