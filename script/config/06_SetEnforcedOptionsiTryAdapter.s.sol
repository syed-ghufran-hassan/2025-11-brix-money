// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

/**
 * @title SetEnforcedOptionsiTryAdapter06
 * @notice Configures enforced options on iTRY Adapter (Sepolia) for hub→spoke transfers
 * @dev This sets minimum gas requirements for SEND messages back to OP Sepolia
 *      to ensure iTRY tokens are properly delivered on the spoke chain.
 *
 *      Critical for:
 *      - Unstaking flow: Ensures iTRY return leg has sufficient gas
 *      - Refund flow: Guarantees VaultComposer._refund() works correctly
 *      - Direct bridge: Provides defensive gas minimum for all iTRY transfers
 */
contract SetEnforcedOptionsiTryAdapter06 is Script {
    using OptionsBuilder for bytes;

    uint32 internal constant OP_SEPOLIA_EID = 40232;
    uint16 internal constant SEND = 1; // msgType for regular send (no compose)
    uint128 internal constant LZ_RECEIVE_GAS = 200000;

    function run() public {
        require(block.chainid == 11155111, "Must run on Sepolia");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address itryAdapter = vm.envAddress("HUB_ITRY_ADAPTER");

        console2.log("========================================");
        console2.log("SETTING ENFORCED OPTIONS - ITRY ADAPTER");
        console2.log("========================================");
        console2.log("iTRY Adapter:", itryAdapter);
        console2.log("Destination EID:", OP_SEPOLIA_EID, "(OP Sepolia)");
        console2.log("MsgType:", SEND, "(SEND - no compose)");
        console2.log("lzReceive gas:", LZ_RECEIVE_GAS);
        console2.log("=========================================\n");

        // Build enforced options with lzReceive only
        // This provides minimum gas for OFT token minting on spoke chain
        bytes memory enforcedOptions = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0);

        console2.log("Enforced options length:", enforcedOptions.length);
        console2.logBytes(enforcedOptions);

        // Create EnforcedOptionParam array
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        params[0] = EnforcedOptionParam({
            eid: OP_SEPOLIA_EID,
            msgType: SEND,
            options: enforcedOptions
        });

        vm.startBroadcast(deployerKey);

        // Set enforced options
        console2.log("\nSetting enforced options...");
        IOAppOptionsType3(itryAdapter).setEnforcedOptions(params);

        vm.stopBroadcast();

        console2.log("\n[OK] Enforced options set successfully!");
        console2.log("\n========================================");
        console2.log("VERIFICATION");
        console2.log("========================================");
        console2.log("Run the following command to verify:");
        console2.log('cast call $HUB_ITRY_ADAPTER "enforcedOptions(uint32,uint16)" 40232 1 --rpc-url $SEPOLIA_RPC_URL');
        console2.log("\nExpected output: Encoded options bytes matching above");
        console2.log("\n========================================");
        console2.log("IMPACT");
        console2.log("========================================");
        console2.log("These enforced options ensure:");
        console2.log("1. Unstaking return leg has guaranteed gas");
        console2.log("2. VaultComposer._refund() works with empty options");
        console2.log("3. All iTRY hub->spoke transfers have minimum gas safety");
        console2.log("========================================");
    }
}
