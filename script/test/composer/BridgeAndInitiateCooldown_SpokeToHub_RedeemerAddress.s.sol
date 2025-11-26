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
 * @title BridgeAndInitiateCooldown_SpokeToHub_RedeemerAddress
 * @notice Bridge wiTRY shares from Spoke to Hub and initiate cooldown for async redemption
 * @dev This script performs:
 *      1. Bridges wiTRY shares from Spoke (OP Sepolia) to Hub (Sepolia)
 *      2. wiTryVaultComposer receives shares via lzCompose
 *      3. wiTryVaultComposer initiates cooldown via cooldownShares()
 *      4. After cooldown period (~3 days), unstake must be called manually
 *
 * Usage:
 *   REDEEM_AMOUNT=5000000000000000000 forge script script/test/composer/BridgeAndInitiateCooldown_SpokeToHub_RedeemerAddress.s.sol --rpc-url $OP_SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - REDEEM_AMOUNT: Amount of wiTRY shares in wei (e.g., 5e18 = 5000000000000000000)
 *   - SPOKE_SHARE_OFT: wiTRY OFT address on spoke chain (OP Sepolia)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (Sepolia = 40161)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 *
 * Prerequisites:
 *   - Enforced options must be set on wiTRY OFT (run 03_SetEnforcedOptionsShareOFT.s.sol)
 *   - Redeemer must have wiTRY shares on Spoke chain
 *   - Redeemer must have ETH for gas fees on Spoke chain
 *
 * Note: This initiates async redemption. After cooldown ends, call unstake() on hub chain.
 */
contract BridgeAndInitiateCooldown_SpokeToHub_RedeemerAddress is Script {
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

        console2.log("========================================");
        console2.log("BRIDGE + INITIATE COOLDOWN - REDEEMER");
        console2.log("========================================");
        console2.log("Flow: Spoke -> Hub (async redeem)");
        console2.log("Operation: Bridge wiTRY + Initiate Cooldown");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("Spoke wiTRY OFT:", spokeShareOFT);
        console2.log("wiTryVaultComposer:", vaultComposer);
        console2.log("Hub EID:", hubEid);
        console2.log("Redeem Amount:", redeemAmount / 1e18, "wiTRY shares");
        console2.log("=========================================\n");

        // Check wiTRY share balance on Spoke
        address shareToken = IOFT(spokeShareOFT).token();
        uint256 balance = IERC20(shareToken).balanceOf(redeemerAddress);
        console2.log("Redeemer wiTRY balance on Spoke:", balance / 1e18, "wiTRY");
        require(balance >= redeemAmount, "Redeemer has insufficient wiTRY balance");

        // Build compose message for async redemption
        // The oftCmd="INITIATE_COOLDOWN" triggers wiTryVaultComposer to call cooldownShares
        SendParam memory composeSendParam = SendParam({
            dstEid: 0, // Not used for async redeem
            to: bytes32(uint256(uint160(redeemerAddress))),
            amountLD: 0, // Not used for async redeem
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: bytes("INITIATE_COOLDOWN") // CRITICAL: Triggers cooldown
        });

        // Encode compose message: (SendParam, minMsgValue)
        bytes memory composeMsg = abi.encode(composeSendParam, uint256(0));

        // Build options: Use only TYPE_3 header, rely on enforced options
        // Enforced options on wiTRY OFT already provide: lzReceive + lzCompose gas
        bytes memory options = OptionsBuilder.newOptions();

        console2.log("Compose message length:", composeMsg.length, "bytes");
        console2.log("Options:", "TYPE_3 (relying on enforced options)");
        console2.log("oftCmd:", "INITIATE_COOLDOWN\n");

        // Build main SendParam: Send wiTRY shares to wiTryVaultComposer with compose
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: bytes32(uint256(uint160(vaultComposer))),
            amountLD: redeemAmount,
            minAmountLD: 0, // No slippage protection for POC
            extraOptions: options,
            composeMsg: composeMsg, // Triggers handleCompose on VaultComposer
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

        // Execute bridge + cooldown initiation
        console2.log("Sending bridge + initiate cooldown transaction...");
        console2.log("  1. Bridging", redeemAmount / 1e18, "wiTRY from Spoke to Hub");
        console2.log("  2. wiTryVaultComposer will initiate cooldown");
        console2.log("  3. After cooldown (~3 days), call unstake() on Hub\n");

        bytes32 guid = IOFT(spokeShareOFT).send{value: fee.nativeFee}(sendParam, fee, redeemerAddress);

        vm.stopBroadcast();

        console2.log("\n=========================================");
        console2.log("[OK] Bridge + Initiate Cooldown transaction sent!");
        console2.log("LayerZero GUID:", vm.toString(guid));
        console2.log("\nExpected outcome:");
        console2.log("  1. wiTRY shares burned on Spoke");
        console2.log("  2. wiTRY shares received by wiTryVaultComposer on Hub");
        console2.log("  3. wiTryVaultComposer initiates cooldown via cooldownShares()");
        console2.log("  4. Cooldown period starts (~3 days)");
        console2.log("  5. After cooldown, call unstake() on Hub to get iTRY");
        console2.log("\nVerify cooldown initiated:");
        console2.log("  cast call $STAKING_VAULT \\");
        console2.log("    \"cooldowns(address)((uint104,uint256))\" \\");
        console2.log("    ", redeemerAddress, "\\");
        console2.log("    --rpc-url $SEPOLIA_RPC_URL");
        console2.log("\nTrack your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("=========================================");
    }
}
