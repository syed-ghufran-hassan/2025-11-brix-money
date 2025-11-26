// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IUnstakeMessenger
 * @notice Interface for the UnstakeMessenger contract on spoke chains
 * @dev Enables users to request crosschain unstaking from spoke to hub
 */
interface IUnstakeMessenger {
    // ============ Structs ============

    /**
     * @notice Unstake message payload sent to hub chain
     * @param user Address that should receive the unstaked iTRY on spoke chain
     * @param extraOptions LayerZero gas options for the return trip (Hub → Spoke)
     */
    struct UnstakeMessage {
        address user;
        bytes extraOptions;
    }

    // ============ Events ============

    /**
     * @notice Emitted when a crosschain unstake request is sent
     * @param user Address requesting the unstake
     * @param hubEid Destination endpoint ID (hub chain)
     * @param totalFee LayerZero fee paid (actual fee used)
     * @param excessRefunded Amount refunded to user (buffer excess)
     * @param guid LayerZero message GUID
     */
    event UnstakeRequested(
        address indexed user, uint32 indexed hubEid, uint256 totalFee, uint256 excessRefunded, bytes32 guid
    );

    /**
     * @notice Emitted when fee buffer is updated
     * @param oldBufferBPS Previous buffer value
     * @param newBufferBPS New buffer value
     */
    event FeeBufferUpdated(uint256 oldBufferBPS, uint256 newBufferBPS);

    /**
     * @notice Emitted when tokens are rescued from the contract
     * @param token The address of the token rescued (address(0) for ETH)
     * @param to The address receiving the rescued tokens
     * @param amount The amount rescued
     */
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    // ============ Errors ============

    /**
     * @notice Thrown when insufficient fee is provided for LayerZero message
     * @param required Required fee amount
     * @param provided Provided fee amount
     */
    error InsufficientFee(uint256 required, uint256 provided);

    /**
     * @notice Thrown when hub endpoint ID is not configured
     */
    error HubNotConfigured();

    /**
     * @notice Thrown when returnTripAllocation is zero
     */
    error InvalidReturnTripAllocation();

    /**
     * @notice Thrown when a zero amount is provided where it's not allowed
     */
    error ZeroAmount();

    /**
     * @notice Thrown when a transfer fails
     */
    error TransferFailed();

    /**
     * @notice Thrown when an invalid zero address is provided
     */
    error ZeroAddress();

    // ============ External Functions ============

    /**
     * @notice Request crosschain unstake from spoke to hub
     * @dev Sends LayerZero message to wiTryVaultComposer on hub chain
     * @dev User must have completed cooldown on hub chain or transaction will revert
     * @dev msg.value must cover LayerZero fees for both legs (Spoke→Hub and Hub→Spoke)
     * @param returnTripAllocation Exact native value to forward to hub for return trip (in wei)
     *        This should be the result of calling wiTryVaultComposer.quoteUnstakeReturn()
     * @return guid LayerZero message GUID for tracking
     */
    function unstake(uint256 returnTripAllocation) external payable returns (bytes32 guid);

    /**
     * @notice Quote exact fee for unstake WITH specified return trip allocation
     * @param returnTripValue Exact amount in wei to forward to hub for return trip
     * @return nativeFee Total spoke→hub message fee WITH returnTripValue embedded
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeWithReturnValue(uint256 returnTripValue)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee);

    /**
     * @notice Quote recommended fee for unstake WITH buffer applied
     * @dev Automatically applies feeBufferBPS safety buffer to protect against gas fluctuations
     * @param returnTripValue Exact amount in wei to forward to hub for return trip
     * @return recommendedFee Recommended total fee with buffer applied
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeWithBuffer(uint256 returnTripValue)
        external
        view
        returns (uint256 recommendedFee, uint256 lzTokenFee);

    /**
     * @notice Set the peer contract address on the hub chain
     * @param hubEid Hub chain endpoint ID
     * @param peer wiTryVaultComposer address on hub (bytes32 encoded)
     */
    function setPeer(uint32 hubEid, bytes32 peer) external;

    /**
     * @notice Get the configured peer for the hub chain
     * @return peer Peer contract address (bytes32 encoded)
     */
    function getHubPeer() external view returns (bytes32 peer);

    // ============ View Functions ============

    /**
     * @notice Get the hub chain endpoint ID
     * @return Hub chain EID
     */
    function hubEid() external view returns (uint32);

    /**
     * @notice Get the current fee buffer in basis points
     * @return Fee buffer in BPS (e.g., 1000 = 10%)
     */
    function feeBufferBPS() external view returns (uint256);

    // ============ Admin Functions ============

    /**
     * @notice Update fee buffer percentage
     * @param newBufferBPS New buffer in basis points (e.g., 1000 = 10%)
     */
    function setFeeBufferBPS(uint256 newBufferBPS) external;

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
