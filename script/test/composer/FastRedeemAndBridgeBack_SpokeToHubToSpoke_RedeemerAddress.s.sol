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
 * @title FastRedeemAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress
 * @notice Bridge wiTRY from Spoke to Hub, fast redeem with fee, and bridge iTRY back to Spoke
 * @dev This script performs a complete round-trip operation in one LayerZero transaction:
 *      1. Bridges wiTRY shares from Spoke (OP Sepolia) to Hub (Sepolia)
 *      2. wiTryVaultComposer receives wiTRY via lzCompose and fast redeems (with fee)
 *      3. wiTryVaultComposer automatically bridges resulting iTRY assets back to Spoke
 *
 * Usage:
 *   REDEEM_AMOUNT=5000000000000000000 forge script script/test/composer/FastRedeemAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress.s.sol --rpc-url $OP_SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - REDEEM_AMOUNT: Amount of wiTRY shares in wei (e.g., 5e18 = 5000000000000000000)
 *   - SPOKE_SHARE_OFT: wiTRY OFT address on spoke chain (OP Sepolia)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (Sepolia = 40161)
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain (OP Sepolia = 40232)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 *
 * Prerequisites:
 *   - Enforced options must be set on wiTRY OFT (run 04_SetEnforcedOptionsShareOFT.s.sol)
 *   - Enforced options must be set on iTRY Adapter (run 06_SetEnforcedOptionsiTryAdapter.s.sol)
 *   - Redeemer must have wiTRY shares on Spoke chain
 *   - Redeemer must have ETH for gas fees on Spoke chain
 *
 * Note: Fast redeem bypasses cooldown but incurs a fee. The fee is deducted from redeemed assets.
 *       This combines bridge + fast redeem + bridge in a single cross-chain transaction using compose.
 */
contract FastRedeemAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress is Script {
    using OptionsBuilder for bytes;

    uint128 internal constant LZ_RECEIVE_GAS = 200000;
    uint128 internal constant LZ_COMPOSE_GAS = 500000;
    uint128 internal constant LZ_COMPOSE_VALUE = 0.01 ether; // For return bridge fees

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
        uint32 spokeEid = uint32(vm.envUint("SPOKE_CHAIN_EID"));

        console2.log("==================================================");
        console2.log("FAST REDEEM + BRIDGE BACK - REDEEMER");
        console2.log("==================================================");
        console2.log("Flow: Spoke -> Hub (fast redeem) -> Spoke");
        console2.log("Operation: Bridge wiTRY + Fast Redeem + Bridge iTRY");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("Spoke wiTRY OFT:", spokeShareOFT);
        console2.log("wiTryVaultComposer:", vaultComposer);
        console2.log("Hub EID:", hubEid);
        console2.log("Spoke EID:", spokeEid);
        console2.log("Redeem Amount:", redeemAmount / 1e18, "wiTRY shares");
        console2.log("==================================================\n");

        // Check wiTRY share balance on Spoke
        address shareToken = IOFT(spokeShareOFT).token();
        uint256 balance = IERC20(shareToken).balanceOf(redeemerAddress);
        console2.log("Redeemer wiTRY balance on Spoke:", balance / 1e18, "wiTRY");
        require(balance >= redeemAmount, "Redeemer has insufficient wiTRY balance");

        // Build compose message for fast redemption with bridge back
        // The oftCmd="FAST_REDEEM" triggers wiTryVaultComposer to call fastRedeemThroughComposer
        SendParam memory composeSendParam = SendParam({
            dstEid: spokeEid, // Bridge iTRY back to Spoke
            to: bytes32(uint256(uint160(redeemerAddress))), // Recipient on Spoke
            amountLD: 0, // Will be set by wiTryVaultComposer after fast redeem
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: bytes("FAST_REDEEM") // CRITICAL: Triggers fast redeem
        });

        // Encode compose message: (SendParam, minMsgValue)
        // minMsgValue covers the return leg iTRY bridge fee
        bytes memory composeMsg = abi.encode(composeSendParam, LZ_COMPOSE_VALUE);

        // Build options: gas for lzReceive on Hub + lzCompose for fast redeem + value for return bridge
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0)
            .addExecutorLzComposeOption(0, LZ_COMPOSE_GAS, LZ_COMPOSE_VALUE);

        console2.log("Compose message length:", composeMsg.length, "bytes");
        console2.log("Compose value for return leg:", LZ_COMPOSE_VALUE / 1e15, "finney");
        console2.log("oftCmd:", "FAST_REDEEM\n");

        // Build main SendParam: Send wiTRY shares to wiTryVaultComposer with compose
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: bytes32(uint256(uint160(vaultComposer))),
            amountLD: redeemAmount,
            minAmountLD: 0, // No slippage protection for POC
            extraOptions: options,
            composeMsg: composeMsg, // Triggers handleCompose on wiTryVaultComposer
            oftCmd: ""
        });

        // Get fee quote
        MessagingFee memory fee = IOFT(spokeShareOFT).quoteSend(sendParam, false);
        console2.log("LayerZero fee (Spoke->Hub leg):", fee.nativeFee / 1e15, "finney");
        console2.log("Compose value (Hub->Spoke leg):", LZ_COMPOSE_VALUE / 1e15, "finney");
        console2.log("Total estimated cost:", (fee.nativeFee + LZ_COMPOSE_VALUE) / 1e18, "ETH\n");

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

        // Execute fast redeem + bridge back
        console2.log("Sending fast redeem + bridge back transaction...");
        console2.log("  Phase 1 (Spoke->Hub):");
        console2.log("    - Bridging", redeemAmount / 1e18, "wiTRY from Spoke to Hub");
        console2.log("  Phase 2 (Hub compose):");
        console2.log("    - wiTryVaultComposer fast redeems wiTRY shares (with fee)");
        console2.log("    - Receives iTRY assets immediately (no cooldown)");
        console2.log("  Phase 3 (Hub->Spoke):");
        console2.log("    - Bridging iTRY assets back to Spoke");
        console2.log("    - Final recipient:", redeemerAddress, "\n");

        bytes32 guid = IOFT(spokeShareOFT).send{value: fee.nativeFee}(
            sendParam,
            fee,
            redeemerAddress
        );

        vm.stopBroadcast();

        console2.log("\n==================================================");
        console2.log("[OK] Fast redeem + bridge back transaction sent!");
        console2.log("LayerZero GUID:", vm.toString(guid));
        console2.log("\nExpected outcome:");
        console2.log("  1. wiTRY shares burned on Spoke");
        console2.log("  2. wiTRY shares received by wiTryVaultComposer on Hub");
        console2.log("  3. wiTryVaultComposer fast redeems shares for iTRY (with fee)");
        console2.log("  4. iTRY assets bridged back to Spoke");
        console2.log("  5. Redeemer receives iTRY on Spoke (minus redemption fee)");
        console2.log("\nNOTE: Fast redeem incurs a fee. The redeemed iTRY amount will be");
        console2.log("less than the 1:1 share conversion due to the early exit penalty.");
        console2.log("\nTrack your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("==================================================");
    }
}
