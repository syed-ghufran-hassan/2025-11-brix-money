// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title SetLibraries02
 * @notice Configures send and receive libraries for OApp contracts
 * @dev This script must be run on BOTH chains (hub and spoke) to complete configuration
 *
 * Phase 3.5: Library Configuration (Required before bridging)
 *
 * Prerequisites:
 *   1. Hub deployment complete (iTryTokenAdapter deployed on Sepolia)
 *   2. Spoke deployment complete (iTryTokenOFT deployed on OP Sepolia)
 *   3. Peer configuration complete (setPeer called on both chains)
 *
 * This script solves the "waiting for ULN config" error by explicitly setting
 * the send and receive libraries that LayerZero should use for cross-chain messaging.
 *
 * Usage:
 *   # Step 1: Configure hub chain (Sepolia)
 *   source testnet.env && forge script script/02_SetLibraries.s.sol:SetLibraries02 \
 *     --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
 *
 *   # Step 2: Configure spoke chain (OP Sepolia)
 *   source testnet.env && forge script script/02_SetLibraries.s.sol:SetLibraries02 \
 *     --rpc-url $OP_SEPOLIA_RPC_URL --broadcast -vvv
 *
 * Environment variables required:
 *   - HUB_ITRY_ADAPTER: Address of iTryTokenAdapter on Sepolia
 *   - VAULT_COMPOSER: Address of VaultComposer on Sepolia
 *   - SPOKE_ITRY_OFT: Address of iTryTokenOFT on OP Sepolia
 *   - UNSTAKE_MESSENGER: Address of UnstakeMessenger on OP Sepolia
 *   - DEPLOYER_PRIVATE_KEY: Private key for signing transactions
 *
 * The script auto-detects which chain it's running on and configures accordingly.
 */
contract SetLibraries02 is Script {
    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;

    // LayerZero Endpoint V2 addresses (from LayerZeroDeploymentsRegistry.json)
    address internal constant SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant OP_SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // LayerZero Endpoint IDs (from LayerZeroDeploymentsRegistry.json)
    uint32 internal constant SEPOLIA_EID = 40161;
    uint32 internal constant OP_SEPOLIA_EID = 40232;

    // SendUln302 and ReceiveUln302 addresses for Sepolia (from LayerZeroDeploymentsRegistry.json)
    // Sepolia testnet deployment with EID 40161
    address internal constant SEPOLIA_SEND_LIB = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;
    address internal constant SEPOLIA_RECEIVE_LIB = 0xdAf00F5eE2158dD58E0d3857851c432E34A3A851;

    // SendUln302 and ReceiveUln302 addresses for OP Sepolia (from LayerZeroDeploymentsRegistry.json)
    // OP Sepolia testnet deployment with EID 40232
    address internal constant OP_SEPOLIA_SEND_LIB = 0xB31D2cb502E25B30C651842C7C3293c51Fe6d16f;
    address internal constant OP_SEPOLIA_RECEIVE_LIB = 0x9284fd59B95b9143AF0b9795CAC16eb3C723C9Ca;

    function run() public {
        console2.log("=========================================");
        console2.log("SET LAYERZERO LIBRARIES");
        console2.log("=========================================");
        console2.log("");

        // Load deployer key
        _loadDeployerKey();

        console2.log("Deployer Address:", deployerAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // Detect chain and configure accordingly
        if (block.chainid == 11155111) {
            // Sepolia (Hub Chain)
            _configureHubChain();
        } else if (block.chainid == 11155420) {
            // OP Sepolia (Spoke Chain)
            _configureSpokeChain();
        } else if (block.chainid == 31337) {
            // Anvil - skip configuration
            console2.log("Running on Anvil testnet - skipping library configuration");
            console2.log("(Local testing doesn't require LayerZero library setup)");
        } else {
            revert("Unknown chain - this script only supports Sepolia (11155111) and OP Sepolia (11155420)");
        }

        console2.log("");
        console2.log("=========================================");
        console2.log("LIBRARY CONFIGURATION COMPLETE");
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. If you just configured Sepolia, run this script again on OP Sepolia");
        console2.log("2. If you just configured OP Sepolia, you're done!");
        console2.log("3. Try bridging again with TestnetBridgeTest.s.sol");
        console2.log("=========================================");
    }

    function _loadDeployerKey() internal {
        if (block.chainid == 31337) {
            deployerPrivateKey = ANVIL_DEPLOYER_KEY;
            console2.log("Using Anvil default key for local testing");
        } else {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            console2.log("Using DEPLOYER_PRIVATE_KEY from environment");
        }

        deployerAddress = vm.addr(deployerPrivateKey);
    }

    function _configureHubChain() internal {
        console2.log("Configuring Hub Chain (Sepolia)...");
        console2.log("");

        // Load hub adapter and composer addresses
        address hubAdapter = vm.envAddress("HUB_ITRY_ADAPTER");
        address vaultComposer = vm.envAddress("VAULT_COMPOSER");

        console2.log("Hub Adapter:", hubAdapter);
        console2.log("Vault Composer:", vaultComposer);
        console2.log("Endpoint:", SEPOLIA_ENDPOINT);
        console2.log("Remote Chain: OP Sepolia (EID:", OP_SEPOLIA_EID, ")");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Configure HUB_ITRY_ADAPTER
        console2.log("Configuring HUB_ITRY_ADAPTER libraries...");
        console2.log("  Setting send library:", SEPOLIA_SEND_LIB);
        (bool success,) = SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                hubAdapter,
                OP_SEPOLIA_EID,
                SEPOLIA_SEND_LIB
            )
        );
        require(success, "Failed to set send library for HUB_ITRY_ADAPTER");
        console2.log("  [OK] Send library configured");

        console2.log("  Setting receive library:", SEPOLIA_RECEIVE_LIB);
        (success,) = SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                hubAdapter,
                OP_SEPOLIA_EID,
                SEPOLIA_RECEIVE_LIB,
                0 // gracePeriod = 0 for immediate switch
            )
        );
        require(success, "Failed to set receive library for HUB_ITRY_ADAPTER");
        console2.log("  [OK] Receive library configured");
        console2.log("");

        // Configure VAULT_COMPOSER
        console2.log("Configuring VAULT_COMPOSER libraries...");
        console2.log("  Setting send library:", SEPOLIA_SEND_LIB);
        (success,) = SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                vaultComposer,
                OP_SEPOLIA_EID,
                SEPOLIA_SEND_LIB
            )
        );
        require(success, "Failed to set send library for VAULT_COMPOSER");
        console2.log("  [OK] Send library configured");

        console2.log("  Setting receive library:", SEPOLIA_RECEIVE_LIB);
        (success,) = SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                vaultComposer,
                OP_SEPOLIA_EID,
                SEPOLIA_RECEIVE_LIB,
                0 // gracePeriod = 0 for immediate switch
            )
        );
        require(success, "Failed to set receive library for VAULT_COMPOSER");
        console2.log("  [OK] Receive library configured");
        console2.log("");

        vm.stopBroadcast();

        console2.log("[OK] Hub chain configuration complete");
    }

    function _configureSpokeChain() internal {
        console2.log("Configuring Spoke Chain (OP Sepolia)...");
        console2.log("");

        // Load spoke OFT and messenger addresses
        address spokeOFT = vm.envAddress("SPOKE_ITRY_OFT");
        address unstakeMessenger = vm.envAddress("UNSTAKE_MESSENGER");

        console2.log("Spoke OFT:", spokeOFT);
        console2.log("Unstake Messenger:", unstakeMessenger);
        console2.log("Endpoint:", OP_SEPOLIA_ENDPOINT);
        console2.log("Remote Chain: Sepolia (EID:", SEPOLIA_EID, ")");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Configure SPOKE_ITRY_OFT
        console2.log("Configuring SPOKE_ITRY_OFT libraries...");
        console2.log("  Setting send library:", OP_SEPOLIA_SEND_LIB);
        (bool success,) = OP_SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                spokeOFT,
                SEPOLIA_EID,
                OP_SEPOLIA_SEND_LIB
            )
        );
        require(success, "Failed to set send library for SPOKE_ITRY_OFT");
        console2.log("  [OK] Send library configured");

        console2.log("  Setting receive library:", OP_SEPOLIA_RECEIVE_LIB);
        (success,) = OP_SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                spokeOFT,
                SEPOLIA_EID,
                OP_SEPOLIA_RECEIVE_LIB,
                0 // gracePeriod = 0 for immediate switch
            )
        );
        require(success, "Failed to set receive library for SPOKE_ITRY_OFT");
        console2.log("  [OK] Receive library configured");
        console2.log("");

        // Configure UNSTAKE_MESSENGER
        console2.log("Configuring UNSTAKE_MESSENGER libraries...");
        console2.log("  Setting send library:", OP_SEPOLIA_SEND_LIB);
        (success,) = OP_SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                unstakeMessenger,
                SEPOLIA_EID,
                OP_SEPOLIA_SEND_LIB
            )
        );
        require(success, "Failed to set send library for UNSTAKE_MESSENGER");
        console2.log("  [OK] Send library configured");

        console2.log("  Setting receive library:", OP_SEPOLIA_RECEIVE_LIB);
        (success,) = OP_SEPOLIA_ENDPOINT.call(
            abi.encodeWithSignature(
                "setReceiveLibrary(address,uint32,address,uint256)",
                unstakeMessenger,
                SEPOLIA_EID,
                OP_SEPOLIA_RECEIVE_LIB,
                0 // gracePeriod = 0 for immediate switch
            )
        );
        require(success, "Failed to set receive library for UNSTAKE_MESSENGER");
        console2.log("  [OK] Receive library configured");
        console2.log("");

        vm.stopBroadcast();

        console2.log("[OK] Spoke chain configuration complete");
    }
}
