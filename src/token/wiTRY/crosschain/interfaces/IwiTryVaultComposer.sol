// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IwiTryVaultComposer
 * @notice Interface for wiTryVaultComposer contract with async redemption support
 * @dev Defines events and errors specific to wiTryVaultComposer async redemption functionality
 */
interface IwiTryVaultComposer {
    // ============================================================================
    // Events
    // ============================================================================

    /**
     * @notice Emitted when async redemption (cooldown) is initiated for a user
     * @param user The bytes32 identifier of the user (cross-chain compatible)
     * @param owner The address of the owner on the hub chain
     * @param shareAmount The number of shares being redeemed
     * @param assetAmount The number of assets locked in cooldown
     */
    event CooldownInitiated(bytes32 indexed user, address indexed owner, uint256 shareAmount, uint256 assetAmount);

    /**
     * @notice Emitted when crosschain unstake is processed successfully
     * @param user Address that requested unstake
     * @param srcEid Source chain endpoint ID
     * @param assets Amount of iTRY unstaked
     * @param guid Message GUID
     */
    event CrosschainUnstakeProcessed(address indexed user, uint32 indexed srcEid, uint256 assets, bytes32 guid);

    /**
     * @notice Emitted when tokens are rescued from the contract
     * @param token The address of the token rescued (address(0) for ETH)
     * @param to The address receiving the rescued tokens
     * @param amount The amount rescued
     */
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    /**
     * @notice Emitted when crosschain fast redeem is processed successfully
     * @param user Address that requested fast redeem
     * @param srcEid Source chain endpoint ID
     * @param shares Amount of shares redeemed
     * @param assets Amount of iTRY redeemed
     */
    event CrosschainFastRedeemProcessed(address indexed user, uint32 indexed srcEid, uint256 shares, uint256 assets);

    // ============================================================================
    // Errors
    // ============================================================================

    /**
     * @notice Error emitted when attempting to use synchronous redemption
     * @dev Synchronous redemption is not supported for vaults requiring cooldown periods
     *      Use INITIATE_COOLDOWN command in lzCompose instead
     */
    error SyncRedemptionNotSupported();

    /**
     * @notice Error emitted when attempting share operations without INITIATE_COOLDOWN command
     * @dev When sending shares to the wiTryVaultComposer via lzCompose, you must include
     *      oftCmd="INITIATE_COOLDOWN" in the SendParam to trigger async redemption
     */
    error InitiateCooldownRequired();

    /**
     * @notice Error emitted when an invalid origin is provided
     * @dev Thrown during validation of origin information
     */
    error InvalidOrigin();

    /**
     * @notice Error emitted when an invalid zero address is provided
     * @dev Thrown during validation of zero address
     */
    error InvalidZeroAddress();

    /**
     * @notice Thrown when an invalid token address is provided
     */
    error InvalidToken();

    /**
     * @notice Thrown when attempting to rescue with zero balance
     */
    error NoBalance();

    /**
     * @notice Thrown when ETH transfer fails
     */
    error TransferFailed();

    /**
     * @notice Thrown when an unknown message type is received
     * @param msgType The unknown message type
     */
    error UnknownMessageType(uint16 msgType);

    /**
     * @notice Thrown when there are no assets to unstake
     */
    error NoAssetsToUnstake();

    /**
     * @notice Thrown when an invalid amount is provided
     */
    error InvalidAmount();

    /**
     * @notice Thrown when an invalid destination endpoint ID is provided
     */
    error InvalidDestination();

    /**
     * @notice Thrown when there are no assets to redeem
     */
    error NoAssetsToRedeem();

    // ============================================================================
    // Functions
    // ============================================================================

    /**
     * @notice Quote fee for unstake return leg (hub→spoke)
     * @param to Address to receive iTRY on destination chain
     * @param amount Amount of iTRY to send
     * @param dstEid Destination endpoint ID (spoke chain)
     * @return nativeFee Fee in native token for hub→spoke leg
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeReturn(address to, uint256 amount, uint32 dstEid)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);

    /**
     * @notice Quote fee for fast redeem return leg (hub→spoke)
     * @dev Queries the adapter to get LayerZero fee for sending iTRY back to spoke chain
     * @param to Address to receive iTRY on spoke chain
     * @param amount Amount of iTRY to send
     * @param dstEid Destination endpoint ID (spoke chain)
     * @return nativeFee Fee in native token for hub→spoke leg
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteFastRedeemReturn(address to, uint256 amount, uint32 dstEid)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);

    /**
     * @notice Rescue tokens accidentally sent to this contract
     * @dev Only callable by owner. Can rescue both ERC20 tokens and native ETH
     *      Use address(0) for rescuing ETH
     * @param token The token address to rescue (use address(0) for ETH)
     * @param to The address to send rescued tokens to
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external;
}
