// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConfigurePeers01
 * @notice Configures bidirectional peer relationships between hub and spoke chains
 * @dev This script should be run AFTER deploying both hub and spoke contracts
 *
 * Phase 3: Hub → Spoke Peer Configuration
 *
 * Prerequisites:
 *   1. Hub deployment complete (iTryTokenAdapter, ShareOFTAdapter, VaultComposer deployed on Sepolia)
 *   2. Spoke deployment complete (iTryTokenOFT, ShareOFT, UnstakeMessenger deployed on OP Sepolia)
 *   3. Spoke contracts already configured their peers (spoke → hub) in SpokeChainDeployment
 *   4. This script completes the bidirectional setup by configuring hub → spoke
 *
 * Usage:
 *   1. Update testnet.env with all required addresses:
 *      - HUB_ITRY_ADAPTER (from Phase 1)
 *      - HUB_SHARE_ADAPTER (from Phase 1)
 *      - VAULT_COMPOSER (from Phase 1)
 *      - SPOKE_ITRY_OFT (from Phase 2)
 *      - SPOKE_SHARE_OFT (from Phase 2)
 *      - UNSTAKE_MESSENGER (from Phase 6)
 *
 *   2. Run via Makefile:
 *      make configure-peers
 *
 *   OR run directly:
 *      source testnet.env && forge script script/config/01_ConfigurePeers.s.sol:ConfigurePeers \
 *        --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
 *
 * Environment variables required:
 *   - HUB_ITRY_ADAPTER: Address of iTryTokenAdapter on hub chain
 *   - HUB_SHARE_ADAPTER: Address of ShareOFTAdapter on hub chain
 *   - VAULT_COMPOSER: Address of VaultComposer on hub chain
 *   - SPOKE_ITRY_OFT: Address of iTryTokenOFT on spoke chain
 *   - SPOKE_SHARE_OFT: Address of ShareOFT on spoke chain
 *   - UNSTAKE_MESSENGER: Address of UnstakeMessenger on spoke chain
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain (default: 40232 for OP Sepolia)
 *
 * Important Note:
 *   VaultComposer→UnstakeMessenger peer enables VaultComposer to receive unstake requests
 *   from spoke chain. The iTRY return path uses iTryTokenAdapter→iTryTokenOFT, not back
 *   through UnstakeMessenger.
 */
contract ConfigurePeers01 is Script {
    // Default LayerZero EIDs
    uint32 internal constant OP_SEPOLIA_EID = 40232;
    uint32 internal constant ARB_SEPOLIA_EID = 40231;
    uint32 internal constant BASE_SEPOLIA_EID = 40245;

    struct PeerConfig {
        address hubITryAdapter;
        address hubShareAdapter;
        address hubVaultComposer;
        address spokeITryOFT;
        address spokeShareOFT;
        address spokeUnstakeMessenger;
        uint32 spokeEid;
    }

            // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    

        // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;

    function run() public {
        // Use Anvil default key for local testing (chainId 31337)
        // Otherwise require DEPLOYER_PRIVATE_KEY environment variable
        if (block.chainid == 31337) {
            deployerPrivateKey = ANVIL_DEPLOYER_KEY;
            console2.log("Using Anvil default key for local testing");
        } else {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            console2.log("Using DEPLOYER_PRIVATE_KEY from environment");
        }
        
        deployerAddress = vm.addr(deployerPrivateKey);
        
        // Load configuration from environment
        PeerConfig memory config = _loadConfig();

        // Validate configuration
        _validateConfig(config);

        // Display configuration
        _displayConfig(config);

        // Configure peers
        vm.startBroadcast(deployerPrivateKey);
        _configurePeers(config);
        vm.stopBroadcast();

        // Display summary
        _displaySummary(config);
    }

    function _loadConfig() internal view returns (PeerConfig memory config) {
        // Load hub adapter addresses from environment variables
        config.hubITryAdapter = vm.envAddress("HUB_ITRY_ADAPTER");
        config.hubShareAdapter = vm.envAddress("HUB_SHARE_ADAPTER");
        config.hubVaultComposer = vm.envAddress("VAULT_COMPOSER");

        // Load spoke chain configuration from environment variables
        config.spokeEid = uint32(vm.envOr("SPOKE_CHAIN_EID", uint256(OP_SEPOLIA_EID)));
        config.spokeITryOFT = vm.envAddress("SPOKE_ITRY_OFT");
        config.spokeShareOFT = vm.envAddress("SPOKE_SHARE_OFT");
        config.spokeUnstakeMessenger = vm.envAddress("UNSTAKE_MESSENGER");
    }

    function _validateConfig(PeerConfig memory config) internal pure {
        // Verify all addresses are set (loaded from environment variables)
        require(config.hubITryAdapter != address(0), "Hub iTRY adapter is zero");
        require(config.hubShareAdapter != address(0), "Hub Share adapter is zero");
        require(config.hubVaultComposer != address(0), "Hub VaultComposer is zero");
        require(config.spokeITryOFT != address(0), "Spoke iTRY OFT is zero");
        require(config.spokeShareOFT != address(0), "Spoke Share OFT is zero");
        require(config.spokeUnstakeMessenger != address(0), "Spoke UnstakeMessenger is zero");
        require(config.spokeEid != 0, "Spoke EID is zero");
    }

    function _displayConfig(PeerConfig memory config) internal view {
        console2.log("=========================================");
        console2.log("CONFIGURE HUB->SPOKE PEER RELATIONSHIPS");
        console2.log("=========================================");
        console2.log("");
        console2.log("Hub Chain (Sepolia):");
        console2.log("  iTryTokenAdapter:", config.hubITryAdapter);
        console2.log("  ShareOFTAdapter:", config.hubShareAdapter);
        console2.log("  VaultComposer:", config.hubVaultComposer);
        console2.log("");
        console2.log("Spoke Chain (EID:", config.spokeEid, "):");
        console2.log("  iTryTokenOFT:", config.spokeITryOFT);
        console2.log("  ShareOFT:", config.spokeShareOFT);
        console2.log("  UnstakeMessenger:", config.spokeUnstakeMessenger);
        console2.log("");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", msg.sender);
        console2.log("=========================================");
        console2.log("");
    }

    function _configurePeers(PeerConfig memory config) internal {
        console2.log("Configuring hub adapters to recognize spoke OFTs...");
        console2.log("");
        
        // Check ownership of hub adapters
        address iTryAdapterOwner = Ownable(config.hubITryAdapter).owner();
        address shareAdapterOwner = Ownable(config.hubShareAdapter).owner();
        
        console2.log("Ownership Check:");
        console2.log("  iTryTokenAdapter owner:", iTryAdapterOwner);
        console2.log("  ShareOFTAdapter owner:", shareAdapterOwner);
        console2.log("  Current broadcaster:", msg.sender);
        console2.log("");
        
        if (iTryAdapterOwner != msg.sender) {
            console2.log("  [WARNING] Broadcaster is NOT owner of iTryTokenAdapter!");
        }
        if (shareAdapterOwner != msg.sender) {
            console2.log("  [WARNING] Broadcaster is NOT owner of ShareOFTAdapter!");
        }
        console2.log("");

        // Configure iTryTokenAdapter to recognize iTryTokenOFT on spoke chain
        bytes32 spokeITryPeer = bytes32(uint256(uint160(config.spokeITryOFT)));
        console2.log("Setting iTryTokenAdapter peer...");
        console2.log("  Spoke EID:", config.spokeEid);
        console2.log("  Spoke OFT (bytes32):", vm.toString(spokeITryPeer));
        
        IOAppCore(config.hubITryAdapter).setPeer(config.spokeEid, spokeITryPeer);
        console2.log("  [OK] iTryTokenAdapter peer configured");
        console2.log("");

        // Configure ShareOFTAdapter to recognize ShareOFT on spoke chain
        bytes32 spokeSharePeer = bytes32(uint256(uint160(config.spokeShareOFT)));
        console2.log("Setting ShareOFTAdapter peer...");
        console2.log("  Spoke EID:", config.spokeEid);
        console2.log("  Spoke OFT (bytes32):", vm.toString(spokeSharePeer));

        IOAppCore(config.hubShareAdapter).setPeer(config.spokeEid, spokeSharePeer);
        console2.log("  [OK] ShareOFTAdapter peer configured");
        console2.log("");

        // Configure VaultComposer to recognize UnstakeMessenger on spoke chain
        bytes32 spokeUnstakePeer = bytes32(uint256(uint160(config.spokeUnstakeMessenger)));
        console2.log("Setting VaultComposer peer...");
        console2.log("  Spoke EID:", config.spokeEid);
        console2.log("  Spoke UnstakeMessenger (bytes32):", vm.toString(spokeUnstakePeer));

        IOAppCore(config.hubVaultComposer).setPeer(config.spokeEid, spokeUnstakePeer);
        console2.log("  [OK] VaultComposer peer configured");
        console2.log("");
    }

    function _displaySummary(PeerConfig memory config) internal view {
        console2.log("=========================================");
        console2.log("PEER CONFIGURATION COMPLETE!");
        console2.log("=========================================");
        console2.log("");
        console2.log("Bidirectional peer relationships established:");
        console2.log("");
        console2.log("iTRY Token Bridge:");
        console2.log("  Hub (Sepolia):", config.hubITryAdapter);
        console2.log("  <->");
        console2.log("  Spoke (EID", config.spokeEid, "):", config.spokeITryOFT);
        console2.log("");
        console2.log("wiTRY Share Bridge:");
        console2.log("  Hub (Sepolia):", config.hubShareAdapter);
        console2.log("  <->");
        console2.log("  Spoke (EID", config.spokeEid, "):", config.spokeShareOFT);
        console2.log("");
        console2.log("Crosschain Unstake:");
        console2.log("  Hub (Sepolia):", config.hubVaultComposer);
        console2.log("  <--");
        console2.log("  Spoke (EID", config.spokeEid, "):", config.spokeUnstakeMessenger);
        console2.log("  (Note: iTRY return path uses iTryTokenAdapter->iTryTokenOFT)");
        console2.log("");
        console2.log("=========================================");
        console2.log("NEXT STEPS:");
        console2.log("=========================================");
        console2.log("1. Verify peer configuration:");
        console2.log("   make verify-sepolia");
        console2.log("   make verify-op-sepolia");
        console2.log("");
        console2.log("2. Test cross-chain bridging:");
        console2.log("   - Bridge iTRY from Sepolia to OP Sepolia");
        console2.log("   - Bridge iTRY from OP Sepolia back to Sepolia");
        console2.log("   - Check balances on both chains");
        console2.log("");
        console2.log("3. Test crosschain unstaking:");
        console2.log("   - Initiate unstake from spoke chain via UnstakeMessenger");
        console2.log("   - Verify VaultComposer receives and processes unstake");
        console2.log("   - Verify iTRY returns via iTryTokenAdapter->iTryTokenOFT");
        console2.log("");
        console2.log("4. Update frontend configuration:");
        console2.log("   - Copy contract addresses to frontend/src/utils/constants.js");
        console2.log("   - Configure network settings for Sepolia + OP Sepolia");
        console2.log("=========================================");
        console2.log("");
    }
}
