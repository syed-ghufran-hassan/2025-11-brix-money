// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

/**
 * @title BridgeWITRY_HubToSpoke_Staker1
 * @notice Bridge wiTRY shares from Hub (Sepolia) to Spoke (OP Sepolia) using Staker1 account
 * @dev Usage:
 *   BRIDGE_AMOUNT=10000000000000000000 forge script script/test/bridge/BridgeWITRY_HubToSpoke_Staker1.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving staker1 key
 *   - BRIDGE_AMOUNT: Amount in wei (e.g., 10e18 = 10000000000000000000)
 *   - HUB_SHARE_ADAPTER: Share Adapter address on hub chain (Sepolia)
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain (OP Sepolia)
 *
 * Alternatively, you can use the STAKER1_KEY environment variable directly:
 *   - STAKER1_KEY: Staker1's private key
 */
contract BridgeWITRY_HubToSpoke_Staker1 is Script {
    using OptionsBuilder for bytes;

    function run() public {
        require(block.chainid == 11155111, "Must run on Sepolia (Hub Chain)");

        // Read environment variables
        uint256 staker1Key;

        // Try to get STAKER1_KEY directly, otherwise derive from DEPLOYER_PRIVATE_KEY
        try vm.envUint("STAKER1_KEY") returns (uint256 key) {
            staker1Key = key;
            console2.log("Using STAKER1_KEY from environment");
        } catch {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            KeyDerivation.ActorKeys memory keys = KeyDerivation.getActorKeys(vm, deployerKey);
            staker1Key = keys.staker1;
            console2.log("Derived staker1 key from DEPLOYER_PRIVATE_KEY");
        }

        address staker1Address = vm.addr(staker1Key);
        uint256 bridgeAmount = vm.envUint("BRIDGE_AMOUNT");
        address shareAdapter = vm.envAddress("HUB_SHARE_ADAPTER");
        uint32 spokeEid = uint32(vm.envUint("SPOKE_CHAIN_EID"));

        console2.log("========================================");
        console2.log("BRIDGE wiTRY: HUB TO SPOKE - STAKER1");
        console2.log("========================================");
        console2.log("Direction: Hub (Sepolia) -> Spoke (OP Sepolia)");
        console2.log("Asset: wiTRY Shares");
        console2.log("Staker1 address:", staker1Address);
        console2.log("Share Adapter (Hub):", shareAdapter);
        console2.log("Destination EID:", spokeEid);
        console2.log("Amount:", bridgeAmount / 1e18, "wiTRY");
        console2.log("=========================================\n");

        // Check staker1 balance
        address shareToken = IOFT(shareAdapter).token();
        uint256 balance = IERC20(shareToken).balanceOf(staker1Address);
        console2.log("Staker1 wiTRY balance on Hub:", balance / 1e18, "wiTRY");
        require(balance >= bridgeAmount, "Staker1 has insufficient balance");

        // Build options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Build SendParam - sending to same staker1 address on spoke chain
        SendParam memory sendParam = SendParam({
            dstEid: spokeEid,
            to: bytes32(uint256(uint160(staker1Address))),
            amountLD: bridgeAmount,
            minAmountLD: bridgeAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Get fee quote
        MessagingFee memory fee = IOFT(shareAdapter).quoteSend(sendParam, false);
        console2.log("LayerZero fee:", fee.nativeFee / 1e15, "finney");
        console2.log("Estimated total cost:", fee.nativeFee / 1e18, "ETH\n");

        // Check ETH balance for fee
        uint256 ethBalance = staker1Address.balance;
        console2.log("Staker1 ETH balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");

        vm.startBroadcast(staker1Key);

        // Approve if needed
        uint256 allowance = IERC20(shareToken).allowance(staker1Address, shareAdapter);
        if (allowance < bridgeAmount) {
            console2.log("Approving wiTRY transfer...");
            IERC20(shareToken).approve(shareAdapter, type(uint256).max);
        }

        // Send
        console2.log("Sending bridge transaction...");
        IOFT(shareAdapter).send{value: fee.nativeFee}(sendParam, fee, staker1Address);

        vm.stopBroadcast();

        console2.log("\n========================================");
        console2.log("[OK] Bridge transaction sent!");
        console2.log("Staker1 will receive", bridgeAmount / 1e18, "wiTRY on OP Sepolia");
        console2.log("Track your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("========================================");
    }
}
