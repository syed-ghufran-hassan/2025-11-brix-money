// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OAppSender, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {OAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";
import {OAppOptionsType3} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingParams} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IUnstakeMessenger.sol";

/**
 * @title UnstakeMessenger
 * @notice User-facing contract on spoke chains for initiating crosschain unstaking operations
 *
 * @dev Part of the iTRY crosschain unstaking system. Key responsibilities:
 *      - Fee quoting: Provides accurate spoke→hub message fees via two quote functions
 *      - Fee validation: Ensures caller sends sufficient native tokens for round-trip messaging
 *      - Native value forwarding: Embeds returnTripAllocation in LayerZero options for hub execution
 *      - Security: Enforces msg.sender as user address (prevents authorization spoofing)
 *      - Refund handling: Returns excess msg.value to user after message dispatch
 *
 * @dev User Flow:
 *      1. Client queries wiTryVaultComposer.quoteUnstakeReturn() on hub to get hub→spoke return fee
 *      2. Client queries quoteUnstakeWithBuffer() (recommended) or quoteUnstakeWithReturnValue() (exact)
 *         - quoteUnstakeWithBuffer(): Applies feeBufferBPS safety margin (e.g., 10%) for gas fluctuations
 *         - quoteUnstakeWithReturnValue(): Returns exact fee without buffer
 *      3. User calls unstake(returnTripAllocation) with quoted total as msg.value
 *      4. Contract calculates spoke→hub fee with embedded returnTripAllocation
 *      5. Contract validates msg.value ≥ total fee, dispatches message, refunds excess to user
 *      6. Hub receives returnTripAllocation as native value for return trip execution
 *
 * @dev Fee Architecture:
 *      - Single msg.value payment covers both message directions (spoke→hub + hub→spoke)
 *      - returnTripAllocation is fixed parameter (not calculated from msg.value remainder)
 *      - Spoke→hub fee = LayerZero messaging cost + returnTripAllocation embedded in options
 *      - Contract embeds returnTripAllocation via addExecutorLzReceiveOption (native value forwarding)
 *      - Hub receives exact returnTripAllocation for return message; hub refunds excess to wiTryVaultComposer
 *      - Spoke refunds any msg.value excess (buffer) to user immediately after dispatch
 *
 * @dev Configuration:
 *      - feeBufferBPS: Recommended safety buffer (500-5000 BPS = 5-50%), adjustable by owner
 *      - hubEid: Immutable hub chain endpoint ID, set at deployment
 *      - peers[hubEid]: Trusted wiTryVaultComposer address on hub (bytes32), set via setPeer()
 */
contract UnstakeMessenger is OAppSender, OAppOptionsType3, ReentrancyGuard, IUnstakeMessenger {
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Message type identifier for unstake operations
    uint16 public constant MSG_TYPE_UNSTAKE = 1;

    /// @notice Basis points denominator for percentage calculations
    /// @dev Standard DeFi convention: 10000 BPS = 100%
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Gas limit for lzReceive on hub chain
    /// @dev Must be non-zero to satisfy LayerZero executor requirements
    uint128 internal constant LZ_RECEIVE_GAS = 350000;

    // ============ State Variables ============

    /// @notice Fee buffer in basis points to protect against gas price fluctuations
    /// @dev Configurable to adapt to different network conditions
    /// @dev Default 10% (1000 bps) follows LayerZero team guidance
    uint256 public feeBufferBPS = 1000;

    /// @notice Endpoint ID of the hub chain (immutable after deployment)
    uint32 public immutable hubEid;

    // ============ Constructor ============

    /**
     * @notice Initialize UnstakeMessenger contract
     * @param _endpoint LayerZero endpoint address on this chain
     * @param _owner Contract owner address
     * @param _hubEid Endpoint ID of the hub chain
     */
    constructor(address _endpoint, address _owner, uint32 _hubEid) OAppCore(_endpoint, _owner) {
        if (_hubEid == 0) revert HubNotConfigured();
        hubEid = _hubEid;
    }

    // ============ External Functions ============

    /**
     * @notice Initiate crosschain unstaking operation
     * @dev User address is always msg.sender (prevents authorization spoofing)
     *      Encodes msg.sender as user in UnstakeMessage
     *      Validates hub peer is configured
     *      Uses fixed returnTripAllocation to avoid circular fee dependency
     *      Protected against reentrancy with nonReentrant modifier
     *
     * @param returnTripAllocation Exact native value to forward to hub for return trip (in wei)
     *        This should be the result of calling  wiTryVaultComposer.quoteUnstakeReturn()
     *
     * @return guid Unique identifier for this LayerZero message
     *
     * @dev Usage:
     *      1. Call wiTryVaultComposer.quoteUnstakeReturn(user, amount, spokeDstEid) on hub
     *      2. Call quoteUnstakeWithReturnValue(returnTripAllocation) or quoteUnstakeWithBuffer(returnTripAllocation) on spoke
     *      3. Call unstake{value: quotedTotal}(returnTripAllocation)
     */
    function unstake(uint256 returnTripAllocation) external payable nonReentrant returns (bytes32 guid) {
        // Validate hub peer configured
        bytes32 hubPeer = peers[hubEid];
        if (hubPeer == bytes32(0)) revert HubNotConfigured();

        // Validate returnTripAllocation
        if (returnTripAllocation == 0) revert InvalidReturnTripAllocation();

        // Build return trip options (valid TYPE_3 header)
        bytes memory extraOptions = OptionsBuilder.newOptions();

        // Encode UnstakeMessage with msg.sender as user (prevents spoofing)
        UnstakeMessage memory message = UnstakeMessage({user: msg.sender, extraOptions: extraOptions});
        bytes memory payload = abi.encode(MSG_TYPE_UNSTAKE, message);

        // Build options WITH native value forwarding for return trip execution
        // casting to 'uint128' is safe because returnTripAllocation value will be less than 2^128
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory callerOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, uint128(returnTripAllocation));
        bytes memory options = _combineOptions(hubEid, MSG_TYPE_UNSTAKE, callerOptions);

        // Quote with native drop included (single quote with fixed returnTripAllocation)
        MessagingFee memory fee = _quote(hubEid, payload, options, false);

        // Validate caller sent enough
        if (msg.value < fee.nativeFee) {
            revert InsufficientFee(fee.nativeFee, msg.value);
        }

        // Automatic refund to msg.sender
        MessagingReceipt memory receipt = _lzSend(
            hubEid,
            payload,
            options,
            fee,
            payable(msg.sender) // Refund excess to user
        );
        guid = receipt.guid;

        emit UnstakeRequested(msg.sender, hubEid, fee.nativeFee, msg.value - fee.nativeFee, guid);

        return guid;
    }

    /**
     * @notice Quote exact fee for unstake WITH specified return trip allocation
     * @dev Returns the precise spoke→hub message fee with embedded native value forwarding.
     *      The contract will forward exactly returnTripValue to hub for the return trip.
     *
     * @dev Usage pattern:
     *      1. Call wiTryVaultComposer.quoteUnstakeReturn() to get hub→spoke return fee
     *      2. Call this function with that fee as returnTripValue
     *      3. Send the returned nativeFee as msg.value to unstake()
     *
     * @param returnTripValue Exact amount in wei to forward to hub for return trip
     * @return nativeFee Total spoke→hub message fee WITH returnTripValue embedded
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeWithReturnValue(uint256 returnTripValue)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        // Build dummy UnstakeMessage for quoting
        UnstakeMessage memory dummyMessage =
            UnstakeMessage({user: address(0), extraOptions: OptionsBuilder.newOptions()});

        bytes memory payload = abi.encode(MSG_TYPE_UNSTAKE, dummyMessage);

        // Build options WITH specified native value
        // This matches what unstake() will do when msg.value = total
        bytes memory callerOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(LZ_RECEIVE_GAS, uint128(returnTripValue));
        bytes memory options = _combineOptions(hubEid, MSG_TYPE_UNSTAKE, callerOptions);

        // Quote with native value included
        MessagingFee memory fee = _quote(hubEid, payload, options, false);

        return (fee.nativeFee, fee.lzTokenFee);
    }

    /**
     * @notice Quote recommended fee for unstake WITH buffer applied
     * @dev Recommended for standard integrations. Automatically applies feeBufferBPS
     *      safety buffer to protect against gas price fluctuations between quote and execution.
     *
     * @dev Usage pattern:
     *      1. Call wiTryVaultComposer.quoteUnstakeReturn() to get hub→spoke return fee
     *      2. Call this function with that fee as returnTripValue
     *      3. Send the returned recommendedFee as msg.value to unstake()
     *      4. Contract uses exact fees; excess buffer refunded to user
     *
     * @param returnTripValue Exact amount in wei to forward to hub for return trip
     * @return recommendedFee Recommended total fee with buffer applied
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeWithBuffer(uint256 returnTripValue)
        external
        view
        returns (uint256 recommendedFee, uint256 lzTokenFee)
    {
        // Get exact fee with return trip value
        (uint256 nativeFee, uint256 lzTokenFeeExact) = this.quoteUnstakeWithReturnValue(returnTripValue);

        // Apply buffer: fee * (10000 + bufferBPS) / 10000
        // Example: 1 ETH fee with 1000 BPS (10%) = 1.1 ETH recommended
        recommendedFee = (nativeFee * (BPS_DENOMINATOR + feeBufferBPS)) / BPS_DENOMINATOR;
        lzTokenFee = lzTokenFeeExact;

        return (recommendedFee, lzTokenFee);
    }

    /**
     * @notice Set trusted peer for crosschain messaging
     * @dev Overrides OAppCore to restrict configuration to hub chain only
     *      Only owner can set peer
     *      Reverts if eid does not equal hubEid
     *      Reverts if peer is zero address
     * @param eid Endpoint ID (must equal hubEid)
     * @param peer Peer address on remote chain (bytes32 format)
     */
    function setPeer(uint32 eid, bytes32 peer) public override(OAppCore, IUnstakeMessenger) onlyOwner {
        require(eid == hubEid, "UnstakeMessenger: Invalid endpoint");
        require(peer != bytes32(0), "UnstakeMessenger: Invalid peer");

        super.setPeer(eid, peer);
    }

    /**
     * @notice Get the configured hub peer address
     * @return peer Hub peer address in bytes32 format
     */
    function getHubPeer() external view returns (bytes32 peer) {
        return peers[hubEid];
    }

    /**
     * @notice Update fee buffer percentage
     * @dev Only owner can adjust buffer to respond to network conditions
     * @param newBufferBPS New buffer in basis points (e.g., 1000 = 10%)
     */
    function setFeeBufferBPS(uint256 newBufferBPS) external onlyOwner {
        require(newBufferBPS >= 500, "Buffer too low (min 5%)");
        require(newBufferBPS <= 5000, "Buffer too high (max 50%)");

        uint256 oldBuffer = feeBufferBPS;
        feeBufferBPS = newBufferBPS;

        emit FeeBufferUpdated(oldBuffer, newBufferBPS);
    }

    /**
     * @notice Allow contract to receive ETH refunds from LayerZero
     * @dev Required because endpoint.send() refunds to address(this)
     */
    receive() external payable {
        // Accept LayerZero refunds silently
        // Owner can rescue if needed
    }

    /**
     * @notice Rescue tokens accidentally sent to this contract
     * @dev Only callable by owner. Can rescue both ERC20 tokens and native ETH
     *      Use address(0) for rescuing ETH
     * @param token The token address to rescue (use address(0) for ETH)
     * @param to The address to send rescued tokens to
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (token == address(0)) {
            // Rescue ETH
            (bool success,) = to.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            // Rescue ERC20 tokens
            IERC20(token).safeTransfer(to, amount);
        }

        emit TokenRescued(token, to, amount);
    }

    /**
     * @notice Internal helper to combine options (works with memory instead of calldata)
     * @dev Wraps the public combineOptions function to work with memory bytes
     * @param _eid Destination endpoint ID
     * @param _msgType Message type
     * @param _extraOptions Extra options in memory
     * @return Combined options bytes
     */
    function _combineOptions(uint32 _eid, uint16 _msgType, bytes memory _extraOptions)
        internal
        view
        returns (bytes memory)
    {
        bytes memory enforced = enforcedOptions[_eid][_msgType];

        // No enforced options, return extra options
        if (enforced.length == 0) {
            return _extraOptions;
        }

        // No extra options, return enforced options
        if (_extraOptions.length <= 2) {
            return enforced;
        }

        // Combine: enforced options + extra options (skip TYPE_3 header from extra)
        return bytes.concat(enforced, _slice(_extraOptions, 2, _extraOptions.length - 2));
    }

    /**
     * @notice Slice bytes array
     * @param _bytes Bytes to slice
     * @param _start Start index
     * @param _length Length to slice
     * @return Sliced bytes
     */
    function _slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(_length);
        for (uint256 i = 0; i < _length; i++) {
            result[i] = _bytes[_start + i];
        }
        return result;
    }
}
