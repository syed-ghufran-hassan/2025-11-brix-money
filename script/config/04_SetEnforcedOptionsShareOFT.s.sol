// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";

/**
 * @title SetEnforcedOptionsShareOFT04
 * @notice Configures enforced options on ShareOFT (OP Sepolia) for async redeem with compose
 * @dev This sets minimum gas requirements for SEND_AND_CALL messages to Sepolia
 *      to ensure lzCompose executes properly on the destination chain
 */
contract SetEnforcedOptionsShareOFT04 is Script {
    using OptionsBuilder for bytes;

    uint32 internal constant SEPOLIA_EID = 40161;
    uint16 internal constant SEND_AND_CALL = 2; // msgType for messages with compose
    uint128 internal constant LZ_RECEIVE_GAS = 200000;
    uint128 internal constant LZ_COMPOSE_GAS = 500000;
    uint128 internal constant LZ_COMPOSE_VALUE = 0.01 ether; // msg.value for compose (covers refund fees)

    function run() public {
        require(block.chainid == 11155420, "Must run on OP Sepolia");

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address spokeShareOFT = vm.envAddress("SPOKE_SHARE_OFT");

        console2.log("========================================");
        console2.log("SETTING ENFORCED OPTIONS - SHARE OFT");
        console2.log("========================================");
        console2.log("ShareOFT:", spokeShareOFT);
        console2.log("Destination EID:", SEPOLIA_EID, "(Sepolia)");
        console2.log("MsgType:", SEND_AND_CALL, "(SEND_AND_CALL)");
        console2.log("lzReceive gas:", LZ_RECEIVE_GAS);
        console2.log("lzCompose gas:", LZ_COMPOSE_GAS);
        console2.log("lzCompose value:", LZ_COMPOSE_VALUE / 1e15, "finney");
        console2.log("=========================================\n");

        // Build enforced options with both lzReceive and lzCompose (with value for refund fees)
        bytes memory enforcedOptions = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(LZ_RECEIVE_GAS, 0)
            .addExecutorLzComposeOption(0, LZ_COMPOSE_GAS, LZ_COMPOSE_VALUE); // index 0, 500k gas, 0.01 ETH value

        console2.log("Enforced options length:", enforcedOptions.length);
        console2.logBytes(enforcedOptions);

        // Create EnforcedOptionParam array
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        params[0] = EnforcedOptionParam({
            eid: SEPOLIA_EID,
            msgType: SEND_AND_CALL,
            options: enforcedOptions
        });

        vm.startBroadcast(deployerKey);

        // Set enforced options
        console2.log("\nSetting enforced options...");
        IOAppOptionsType3(spokeShareOFT).setEnforcedOptions(params);

        vm.stopBroadcast();

        console2.log("\n[OK] Enforced options set successfully!");
        console2.log("\nVerify with:");
        console2.log('cast call $SPOKE_SHARE_OFT "enforcedOptions(uint32,uint16)(bytes)" 40161 2 --rpc-url $OP_SEPOLIA_RPC_URL');
    }
}
