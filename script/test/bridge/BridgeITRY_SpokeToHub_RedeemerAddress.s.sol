// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

/**
 * @title BridgeITRY_SpokeToHub_RedeemerAddress
 * @notice Bridge iTRY tokens from Spoke (OP Sepolia) to Hub (Sepolia) using Redeemer account
 * @dev Usage:
 *   BRIDGE_AMOUNT=10000000000000000000 forge script script/test/bridge/BridgeITRY_SpokeToHub_RedeemerAddress.s.sol --rpc-url $OP_SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - BRIDGE_AMOUNT: Amount in wei (e.g., 10e18 = 10000000000000000000)
 *   - SPOKE_ITRY_OFT: iTRY OFT address on spoke chain (OP Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (Sepolia)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 */
contract BridgeITRY_SpokeToHub_RedeemerAddress is Script {
    using OptionsBuilder for bytes;

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
        address itryOFT = vm.envAddress("SPOKE_ITRY_OFT");
        uint32 hubEid = uint32(vm.envUint("HUB_CHAIN_EID"));

        console2.log("========================================");
        console2.log("BRIDGE iTRY: SPOKE TO HUB - REDEEMER");
        console2.log("========================================");
        console2.log("Direction: Spoke (OP Sepolia) -> Hub (Sepolia)");
        console2.log("Asset: iTRY Tokens");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("iTRY OFT (Spoke):", itryOFT);
        console2.log("Destination EID:", hubEid);
        console2.log("Amount:", bridgeAmount / 1e18, "iTRY");
        console2.log("=========================================\n");

        // Check redeemer balance on spoke chain
        uint256 balance = IERC20(itryOFT).balanceOf(redeemerAddress);
        console2.log("Redeemer iTRY balance on Spoke:", balance / 1e18, "iTRY");
        require(balance >= bridgeAmount, "Redeemer has insufficient balance");

        // Build options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Build SendParam - sending to same redeemer address on hub chain
        SendParam memory sendParam = SendParam({
            dstEid: hubEid,
            to: bytes32(uint256(uint160(redeemerAddress))),
            amountLD: bridgeAmount,
            minAmountLD: bridgeAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Get fee quote
        MessagingFee memory fee = IOFT(itryOFT).quoteSend(sendParam, false);
        console2.log("LayerZero fee:", fee.nativeFee / 1e15, "finney");
        console2.log("Estimated total cost:", fee.nativeFee / 1e18, "ETH\n");

        // Check ETH balance for fee
        uint256 ethBalance = redeemerAddress.balance;
        console2.log("Redeemer ETH balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");

        vm.startBroadcast(redeemerKey);

        // Approve if needed
        uint256 allowance = IERC20(itryOFT).allowance(redeemerAddress, itryOFT);
        if (allowance < bridgeAmount) {
            console2.log("Approving iTRY transfer...");
            IERC20(itryOFT).approve(itryOFT, type(uint256).max);
        }

        // Send
        console2.log("Sending bridge transaction...");
        IOFT(itryOFT).send{value: fee.nativeFee}(sendParam, fee, redeemerAddress);

        vm.stopBroadcast();

        console2.log("\n========================================");
        console2.log("[OK] Bridge transaction sent!");
        console2.log("Redeemer will receive", bridgeAmount / 1e18, "iTRY on Sepolia");
        console2.log("Track your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("========================================");
    }
}
