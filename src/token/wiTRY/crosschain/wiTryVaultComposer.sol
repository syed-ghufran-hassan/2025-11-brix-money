// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {VaultComposerSync} from "./libraries/VaultComposerSync.sol";
import {SendParam, MessagingFee, IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IStakediTryCrosschain} from "../interfaces/IStakediTryCrosschain.sol";
import {IwiTryVaultComposer} from "./interfaces/IwiTryVaultComposer.sol";
import {OApp} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakediTryCrosschain} from "../StakediTryCrosschain.sol";
import {IUnstakeMessenger} from "./interfaces/IUnstakeMessenger.sol";

/**
 * @title wiTryVaultComposer - Async Cooldown Vault Composer
 * @author Inverter Network
 * @notice wiTryVaultComposer that supports deposit-and-send and async cooldown-based redemption
 * @dev Extends VaultComposerSync with custom redemption logic for StakediTryCrosschain vault
 *      Deposits are instant and shares can be sent cross-chain immediately
 *      Redemptions require a cooldown period before claiming assets
 *      OApp inheritance allows direct LayerZero messages for unstake operations
 */
contract wiTryVaultComposer is VaultComposerSync, IwiTryVaultComposer, OApp {
    using OFTComposeMsgCodec for bytes32;
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============

    /**
     * @notice Message type constant for unstake operations
     * @dev Used for routing direct _lzReceive messages from spoke chains
     * @dev Distinct from compose flow which uses oftCmd strings
     */
    uint16 public constant MSG_TYPE_UNSTAKE = 1;

    /**
     * @notice Initializes the wiTryVaultComposer contract
     * @param _vault The address of the StakediTryCrosschain vault contract
     * @param _assetOFT The address of the iTRY asset OFT contract
     * @param _shareOFT The address of the wiTRY share OFT contract
     * @param _endpoint The LayerZero endpoint address
     * @dev Initializes both VaultComposerSync and OApp functionality
     *      Endpoint must be passed explicitly to ensure OApp initialization happens correctly
     */
    constructor(address _vault, address _assetOFT, address _shareOFT, address _endpoint)
        VaultComposerSync(_vault, _assetOFT, _shareOFT)
        OApp(_endpoint, msg.sender)
    {}

    /**
     * @notice Handles composed cross-chain operations with oftCmd routing
     * @param _oftIn The OFT token received in lzReceive
     * @param _composeFrom The bytes32 identifier of the compose sender
     * @param _composeMsg The encoded message containing SendParam and minMsgValue
     * @param _amount The amount of tokens received
     */
    function handleCompose(address _oftIn, bytes32 _composeFrom, bytes memory _composeMsg, uint256 _amount)
        external
        payable
        override
    {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        (SendParam memory sendParam, uint256 minMsgValue) = abi.decode(_composeMsg, (SendParam, uint256));
        if (msg.value < minMsgValue) revert InsufficientMsgValue(minMsgValue, msg.value);

        if (_oftIn == ASSET_OFT) {
            _depositAndSend(_composeFrom, _amount, sendParam, address(this));
        } else if (_oftIn == SHARE_OFT) {
            if (keccak256(sendParam.oftCmd) == keccak256("INITIATE_COOLDOWN")) {
                _initiateCooldown(_composeFrom, _amount);
            } else if (keccak256(sendParam.oftCmd) == keccak256("FAST_REDEEM")) {
                _fastRedeem(_composeFrom, _amount, sendParam, address(this));
            } else {
                revert InitiateCooldownRequired();
            }
        } else {
            revert OnlyValidComposeCaller(_oftIn);
        }
    }

    /**
     * @notice Initiates async redemption via cooldown mechanism
     * @param _redeemer The bytes32 address of the redeemer
     * @param _shareAmount The number of shares to redeem
     */
    function _initiateCooldown(bytes32 _redeemer, uint256 _shareAmount) internal virtual {
        address redeemer = _redeemer.bytes32ToAddress();
        if (redeemer == address(0)) revert InvalidZeroAddress();
        uint256 assetAmount = IStakediTryCrosschain(address(VAULT)).cooldownSharesByComposer(_shareAmount, redeemer);
        emit CooldownInitiated(_redeemer, redeemer, _shareAmount, assetAmount);
    }


    /**
     * @notice Fast redeem shares for immediate withdrawal with a fee
     * @param _redeemer The bytes32 address of the redeemer
     * @param _shareAmount The number of shares to redeem
     * @param _sendParam The send parameters for the crosschain transfer
     * @param _refundAddress The address to receive the refund
     */
    function _fastRedeem(bytes32 _redeemer, uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress) internal virtual {
         address redeemer = _redeemer.bytes32ToAddress();
        if (redeemer == address(0)) revert InvalidZeroAddress();

        uint256 assets = IStakediTryCrosschain(address(VAULT)).fastRedeemThroughComposer(_shareAmount, redeemer, redeemer); // redeemer is the owner and crosschain receiver

          if (assets == 0) {
            revert NoAssetsToRedeem();
        }

        _sendParam.amountLD = assets;
        _sendParam.minAmountLD = assets;

        _send(ASSET_OFT, _sendParam, _refundAddress);

        // Emit success event
        emit CrosschainFastRedeemProcessed(redeemer, _sendParam.dstEid, _shareAmount, assets);

    }

    /**
     * @notice Synchronous redemption is not supported
     * @dev Always reverts - use INITIATE_COOLDOWN command instead
     */
    function _redeemAndSend(
        bytes32,
        /*_redeemer*/
        uint256,
        /*_shareAmount*/
        SendParam memory,
        /*_sendParam*/
        address /*_refundAddress*/
    ) internal virtual override {
        revert SyncRedemptionNotSupported();
    }

    /**
     * @notice Override _refund to include valid extraOptions
     * @dev Ensures extraOptions contains valid TYPE_3 options for LayerZero
     * @param _oft The OFT contract address used for refunding
     * @param _message The original message that was sent
     * @param _amount The amount of tokens to refund
     * @param _refundAddress Address to receive the refund
     */
    function _refund(address _oft, bytes calldata _message, uint256 _amount, address _refundAddress)
        internal
        virtual
        override
    {
        SendParam memory refundSendParam;
        refundSendParam.dstEid = OFTComposeMsgCodec.srcEid(_message);
        refundSendParam.to = OFTComposeMsgCodec.composeFrom(_message);
        refundSendParam.amountLD = _amount;
        refundSendParam.extraOptions = OptionsBuilder.newOptions(); // Add valid TYPE_3 options header (0x0003)

        IOFT(_oft).send{value: msg.value}(refundSendParam, MessagingFee(msg.value, 0), _refundAddress);
    }

    // ============ OAPP INTEGRATION ============

    /**
     * @notice Allow contract to receive ETH for LayerZero operations and refunds
     * @dev Required for:
     *      1. Receiving LayerZero fee refunds from crosschain operations (hub→spoke dust)
     *      2. Accepting ETH for gas forwarding in crosschain unstaking
     *      3. Emergency recovery scenarios
     * @dev wiTryVaultComposer is the refund address for unstake operations to maintain
     *      clean separation between crosschain logic and staking vault logic
     * @dev Overrides parent VaultComposerSync's receive() function
     */
    receive() external payable override {}

    /**
     * @notice Rescue tokens accidentally sent to this contract
     * @dev Only callable by owner. Can rescue both ERC20 tokens and native ETH
     *      Use address(0) for rescuing ETH
     * @param token The token address to rescue (use address(0) for ETH)
     * @param to The address to send rescued tokens to
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidZeroAddress();
        if (amount == 0) revert InvalidAmount();

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
     * @notice Receive crosschain messages from spoke chains
     * @dev Routes messages by type to appropriate handlers
     * @dev SECURITY: LayerZero OApp validates peers before calling _lzReceive()
     *      The authorization model relies on the spoke chain's UnstakeMessenger
     *      validating that only the token owner can initiate unstaking.
     * @param _origin Origin information (source chain and sender)
     * @param _guid Message GUID
     * @param _message Encoded message payload
     * @param _executor Executor address
     * @param _extraData Extra data from LayerZero
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Note: LayerZero OApp handles peer validation before calling _lzReceive().
        // Peer validation is redundant here as the OApp base contract already ensures
        // messages only come from authorized peers configured via setPeer().

        // Decode and route message
        (uint16 msgType, IUnstakeMessenger.UnstakeMessage memory unstakeMsg) =
            abi.decode(_message, (uint16, IUnstakeMessenger.UnstakeMessage));

        if (msgType == MSG_TYPE_UNSTAKE) {
            _handleUnstake(_origin, _guid, unstakeMsg);
        } else {
            revert UnknownMessageType(msgType);
        }
    }

    /**
     * @notice Process unstake requests from spoke chains
     * @dev Validates user address and cooldown state, calls vault to unstake,
     *      and sends the unstaked iTRY assets back to the user on the spoke chain
     * @param _origin Origin information (source chain and sender)
     * @param _guid Message GUID
     * @param unstakeMsg Unstake message containing user address and extraOptions
     */
    function _handleUnstake(Origin calldata _origin, bytes32 _guid, IUnstakeMessenger.UnstakeMessage memory unstakeMsg)
        internal
        virtual
    {
        address user = unstakeMsg.user;

        // Validate user
        if (user == address(0)) revert InvalidZeroAddress();
        if (_origin.srcEid == 0) revert InvalidOrigin();

        // Call vault to unstake
        uint256 assets = IStakediTryCrosschain(address(VAULT)).unstakeThroughComposer(user);

        if (assets == 0) {
            revert NoAssetsToUnstake();
        }

        // Build send parameters and send assets back to spoke chain
        bytes memory options = OptionsBuilder.newOptions();

        SendParam memory _sendParam = SendParam({
            dstEid: _origin.srcEid,
            to: bytes32(uint256(uint160(user))),
            amountLD: assets,
            minAmountLD: assets,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        _send(ASSET_OFT, _sendParam, address(this));

        // Emit success event
        emit CrosschainUnstakeProcessed(user, _origin.srcEid, assets, _guid);
    }

    /**
     * @notice Quote fee for unstake return leg (hub→spoke)
     * @dev Queries the adapter to get LayerZero fee for sending iTRY back to spoke chain
     *      Used by test scripts and potential frontend to calculate total round-trip cost
     * @dev Gas Consideration:
     * - Enforced options on adapter already include 200k gas
     * - Quote automatically includes gas cost
     * - No need to calculate vault execution gas (already happened on hub)
     *
     * @param to Address to receive iTRY on destination chain
     * @param amount Amount of iTRY to send
     * @param dstEid Destination endpoint ID (spoke chain)
     * @return nativeFee Fee in native token for hub→spoke leg
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteUnstakeReturn(address to, uint256 amount, uint32 dstEid)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        // Validate inputs
        if (to == address(0)) revert InvalidZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (dstEid == 0) revert InvalidDestination();

        // Build send parameters for vault composer's _send() function
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: OptionsBuilder.newOptions(), // Adapter enforced options provide gas
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee from the adapter
        // Note: This uses the adapter's quoteSend (OFT), not wiTryVaultComposer's _quote (OApp)
        // The adapter already has enforced options with 200k gas set
        MessagingFee memory fee = IOFT(ASSET_OFT).quoteSend(sendParam, false);

        return (fee.nativeFee, fee.lzTokenFee);
    }

    /**
     * @notice Quote fee for fast redeem return leg (spoke→hub)
     * @dev Queries the adapter to get LayerZero fee for sending iTRY back to hub chain
     *      Used by test scripts and potential frontend to calculate total round-trip cost
     * @param to Address to receive iTRY on hub chain
     * @param amount Amount of iTRY to send
     * @param dstEid Destination endpoint ID (hub chain)
     * @return nativeFee Fee in native token for spoke→hub leg
     * @return lzTokenFee Fee in LayerZero token (typically 0)
     */
    function quoteFastRedeemReturn(address to, uint256 amount, uint32 dstEid)
        external
        view
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        // Validate inputs
        if (to == address(0)) revert InvalidZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (dstEid == 0) revert InvalidDestination();

        // Build send parameters for vault composer's _send() function
        SendParam memory sendParam = SendParam({
            dstEid: dstEid,
            to: bytes32(uint256(uint160(to))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: OptionsBuilder.newOptions(), // Adapter enforced options provide gas
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the fee from the adapter
        // Note: This uses the adapter's quoteSend (OFT), not wiTryVaultComposer's _quote (OApp)
        // The adapter already has enforced options with 200k gas set
        MessagingFee memory fee = IOFT(ASSET_OFT).quoteSend(sendParam, false);

        return (fee.nativeFee, fee.lzTokenFee);
    }
}
