// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

interface IOFT {
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (bytes32 guid);

    function quoteSend(
        SendParam calldata _sendParam,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    function token() external view returns (address);
}

/**
 * @title InitiateCooldownRefund_SpokeToHub_RedeemerAddress
 * @notice Tests cooldown initiation refund mechanism by intentionally triggering a failure
 * @dev Sends shares from Spoke to Hub with INVALID_COMMAND to trigger handleCompose failure and test refund flow
 *
 * Usage:
 *   REDEEM_AMOUNT=5000000000000000000 forge script script/test/composer/InitiateCooldownRefund_SpokeToHub_RedeemerAddress.s.sol --rpc-url $OP_SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - REDEEM_AMOUNT: Amount in wei (e.g., 5e18 = 5000000000000000000)
 *   - SPOKE_SHARE_OFT: wiTRY OFT address on spoke chain (OP Sepolia)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (Sepolia)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 *
 * Note: This test intentionally uses an invalid command to trigger the refund mechanism.
 */
contract InitiateCooldownRefund_SpokeToHub_RedeemerAddress is Script {
    using OptionsBuilder for bytes;

    uint128 internal constant LZ_RECEIVE_GAS = 200000;
    uint128 internal constant LZ_COMPOSE_GAS = 500000;

    function run() public {
        require(block.chainid == 11155420, "Must run on OP Sepolia (Spoke Chain)");

        // Read environment variables
        uint256 redeemerKey;

        // Try to get REDEEMER_KEY directly, otherwise derive from DEPLOYER_PRIVATE_KEY
        try vm.envUint("REDEEMER_KEY") returns (uint256 key) {
            redeemerKey = key;
            console2.log("Using REDEEMER_KEY from environment");
        } catch {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            KeyDerivation.ActorKeys memory keys = KeyDerivation.getActorKeys(vm, deployerKey);
            redeemerKey = keys.redeemer;
            console2.log("Derived redeemer key from DEPLOYER_PRIVATE_KEY");
        }

        address redeemerAddress = vm.addr(redeemerKey);
        uint256 redeemAmount = vm.envUint("REDEEM_AMOUNT");
        address spokeShareOFT = vm.envAddress("SPOKE_SHARE_OFT");
        address vaultComposer = vm.envAddress("VAULT_COMPOSER");
        uint32 hubEid = uint32(vm.envUint("HUB_CHAIN_EID"));

        console2.log("=========================================");
        console2.log("INITIATE COOLDOWN REFUND TEST - REDEEMER");
        console2.log("=========================================");
        console2.log("Direction: Spoke (OP Sepolia) -> Hub (Sepolia)");
        console2.log("Operation: Initiate cooldown with INVALID config (tests refund)");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("Spoke wiTRY OFT:", spokeShareOFT);
        console2.log("wiTryVaultComposer:", vaultComposer);
        console2.log("Destination EID:", hubEid);
        console2.log("Redeem Amount:", redeemAmount / 1e18, "wiTRY");
        console2.log("=========================================\n");

        // Check balance
        address shareToken = IOFT(spokeShareOFT).token();
        uint256 balance = IERC20(shareToken).balanceOf(redeemerAddress);
        console2.log("Redeemer wiTRY balance on Spoke:", balance / 1e18, "wiTRY");
        require(balance >= redeemAmount, "Redeemer has insufficient wiTRY balance");

        // Build compose message with INVALID command to trigger refund
        SendParam memory innerSendParam = SendParam({
            dstEid: 0,
            to: bytes32(0),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: "INVALID_COMMAND"  // Invalid command triggers handleCompose failure -> refund
        });
        bytes memory composeMsg = abi.encode(innerSendParam, uint256(0));

        // Build options: Add gas for both lzReceive and lzCompose
        // lzReceive handles the message on hub, lzCompose calls handleCompose
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0)
            .addExecutorLzComposeOption(0, LZ_COMPOSE_GAS, 0);

        console2.log("Compose message length:", composeMsg.length, "bytes");
        console2.log("Options length:", options.length, "bytes");
        console2.log("oftCmd: INVALID_COMMAND (intentional for refund test)\n");

        // Build SendParam
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: bytes32(uint256(uint160(vaultComposer))),
            amountLD: redeemAmount,
            minAmountLD: redeemAmount,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        // Get fee quote
        MessagingFee memory fee = IOFT(spokeShareOFT).quoteSend(sendParam, false);
        console2.log("LayerZero fee:", fee.nativeFee / 1e15, "finney");
        console2.log("Estimated total cost:", fee.nativeFee / 1e18, "ETH\n");

        // Check ETH balance for fee
        uint256 ethBalance = redeemerAddress.balance;
        console2.log("Redeemer ETH balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");

        vm.startBroadcast(redeemerKey);

        // Approve if needed
        uint256 allowance = IERC20(shareToken).allowance(redeemerAddress, spokeShareOFT);
        if (allowance < redeemAmount) {
            console2.log("Approving wiTRY transfer...");
            IERC20(shareToken).approve(spokeShareOFT, type(uint256).max);
        }

        // Send with compose message (will fail on hub and trigger refund)
        console2.log("Sending initiate cooldown transaction with invalid config...");
        IOFT(spokeShareOFT).send{value: fee.nativeFee}(sendParam, fee, redeemerAddress);

        vm.stopBroadcast();

        console2.log("\n=========================================");
        console2.log("[OK] Initiate cooldown refund test transaction sent!");
        console2.log("Expected outcome:");
        console2.log("  1. Shares bridged to Hub");
        console2.log("  2. wiTryVaultComposer handleCompose fails (INVALID_COMMAND)");
        console2.log("  3. Shares refunded back to Redeemer on Spoke");
        console2.log("\nTrack your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("=========================================");
    }
}
