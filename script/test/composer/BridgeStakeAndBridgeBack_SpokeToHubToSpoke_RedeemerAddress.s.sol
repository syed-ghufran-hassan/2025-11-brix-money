// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
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
 * @title BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress
 * @notice Bridge iTRY from Spoke to Hub, stake into vault, and bridge wiTRY shares back to Spoke
 * @dev This script performs a complete round-trip operation in one LayerZero transaction:
 *      1. Bridges iTRY tokens from Spoke (OP Sepolia) to Hub (Sepolia)
 *      2. wiTryVaultComposer receives iTRY via lzCompose and stakes into vault
 *      3. wiTryVaultComposer automatically bridges resulting wiTRY shares back to Spoke
 *
 * Usage:
 *   BRIDGE_AMOUNT=10000000000000000000000 forge script script/test/composer/BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress.s.sol --rpc-url $OP_SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - BRIDGE_AMOUNT: Amount in wei (e.g., 10000e18 = 10000000000000000000000)
 *   - SPOKE_ITRY_OFT: iTRY OFT address on spoke chain (OP Sepolia)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (Sepolia = 40161)
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain (OP Sepolia = 40232)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 *
 * Note: This combines bridge + stake + bridge in a single cross-chain transaction using compose.
 */
contract BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress is Script {
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
        uint256 bridgeAmount = vm.envUint("BRIDGE_AMOUNT");
        address spokeItryOFT = vm.envAddress("SPOKE_ITRY_OFT");
        address vaultComposer = vm.envAddress("VAULT_COMPOSER");
        uint32 hubEid = uint32(vm.envUint("HUB_CHAIN_EID"));
        uint32 spokeEid = uint32(vm.envUint("SPOKE_CHAIN_EID"));

        console2.log("=========================================");
        console2.log("BRIDGE + STAKE + BRIDGE BACK - REDEEMER");
        console2.log("=========================================");
        console2.log("Flow: Spoke -> Hub (stake) -> Spoke");
        console2.log("Operation: Bridge iTRY + Stake + Bridge wiTRY");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("Spoke iTRY OFT:", spokeItryOFT);
        console2.log("wiTryVaultComposer:", vaultComposer);
        console2.log("Hub EID:", hubEid);
        console2.log("Spoke EID:", spokeEid);
        console2.log("Bridge Amount:", bridgeAmount / 1e18, "iTRY");
        console2.log("=========================================\n");

        // Check iTRY balance on Spoke
        address itryToken = IOFT(spokeItryOFT).token();
        uint256 balance = IERC20(itryToken).balanceOf(redeemerAddress);
        console2.log("Redeemer iTRY balance on Spoke:", balance / 1e18, "iTRY");
        require(balance >= bridgeAmount, "Redeemer has insufficient iTRY balance");

        // Build the inner SendParam for the return bridge (wiTRY shares back to Spoke)
        // This tells wiTryVaultComposer: "after staking, send shares back to Spoke"
        SendParam memory returnSendParam = SendParam({
            dstEid: spokeEid,
            to: bytes32(uint256(uint160(redeemerAddress))),
            amountLD: 0, // Will be set to actual shares minted
            minAmountLD: 0, // No slippage protection for POC
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        // Encode compose message: wiTryVaultComposer will decode this in handleCompose
        bytes memory composeMsg = abi.encode(returnSendParam, uint256(LZ_COMPOSE_VALUE));

        // Build options: gas for lzReceive on Hub + lzCompose for staking + value for return bridge
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0)
            .addExecutorLzComposeOption(0, LZ_COMPOSE_GAS, LZ_COMPOSE_VALUE);

        console2.log("Compose message length:", composeMsg.length, "bytes");
        console2.log("Options length:", options.length, "bytes");
        console2.log("Compose value for return bridge:", LZ_COMPOSE_VALUE / 1e15, "finney\n");

        // Build main SendParam: Send iTRY to wiTryVaultComposer on Hub with compose
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: bytes32(uint256(uint160(vaultComposer))),
            amountLD: bridgeAmount,
            minAmountLD: bridgeAmount,
            extraOptions: options,
            composeMsg: composeMsg, // This triggers handleCompose on wiTryVaultComposer
            oftCmd: ""
        });

        // Get fee quote
        MessagingFee memory fee = IOFT(spokeItryOFT).quoteSend(sendParam, false);
        console2.log("LayerZero fee:", fee.nativeFee / 1e15, "finney");
        console2.log("Estimated total cost:", fee.nativeFee / 1e18, "ETH\n");

        // Check ETH balance for fee
        uint256 ethBalance = redeemerAddress.balance;
        console2.log("Redeemer ETH balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");

        vm.startBroadcast(redeemerKey);

        // Approve if needed
        uint256 allowance = IERC20(itryToken).allowance(redeemerAddress, spokeItryOFT);
        if (allowance < bridgeAmount) {
            console2.log("Approving iTRY transfer...");
            IERC20(itryToken).approve(spokeItryOFT, type(uint256).max);
        }

        // Execute the complete flow in one transaction
        console2.log("Sending bridge + stake + bridge back transaction...");
        console2.log("  1. Bridging", bridgeAmount / 1e18, "iTRY from Spoke to Hub");
        console2.log("  2. wiTryVaultComposer will stake iTRY into vault");
        console2.log("  3. wiTryVaultComposer will bridge wiTRY shares back to Spoke\n");

        IOFT(spokeItryOFT).send{value: fee.nativeFee}(sendParam, fee, redeemerAddress);

        vm.stopBroadcast();

        console2.log("\n=========================================");
        console2.log("[OK] Bridge + Stake + Bridge Back transaction sent!");
        console2.log("Expected outcome:");
        console2.log("  1. iTRY burned on Spoke");
        console2.log("  2. iTRY received by wiTryVaultComposer on Hub");
        console2.log("  3. wiTryVaultComposer stakes iTRY, mints wiTRY shares");
        console2.log("  4. wiTryVaultComposer bridges wiTRY shares back to Spoke");
        console2.log("  5. Redeemer receives wiTRY shares on Spoke");
        console2.log("\nTrack your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("=========================================");
    }
}
