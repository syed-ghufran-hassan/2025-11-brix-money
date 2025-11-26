// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 30_ConfigurePeers
 * @notice [HUB] Configures hub adapters to recognize spoke chain OFT contracts
 * @dev This script should be run AFTER deploying both hub and spoke contracts
 *
 * Key changes from v1:
 * - Spoke->Hub configuration is now done in 20_DeploySpoke.s.sol
 * - This script only handles Hub->Spoke configuration
 * - Uses environment variables instead of hardcoded addresses
 * - Contract references updated for v2 (wiTryOFT)
 *
 * Deployment sequence: 10 → 11 → 12 (hub) → 20 (spoke) → 30 (configure peers)
 * Next steps: 32_ConfigureLZLibraries → 40_VerifyHub → 42_VerifyBridge
 *
 * Prerequisites:
 *   1. Hub deployment complete (12_DeployCrossChain ran successfully)
 *   2. Spoke deployment complete (20_DeploySpoke ran successfully)
 *   3. Spoke contracts already configured their peers (spoke->hub) during deployment
 *   4. This script completes bidirectional setup by configuring hub->spoke
 *
 * Usage:
 *   forge script script/30_ConfigurePeers.s.sol:ConfigurePeers \
 *     --rpc-url <HUB_RPC_URL> \
 *     --broadcast \
 *     -vv
 *
 * Environment variables required:
 *   - DEPLOYER_PRIVATE_KEY: Private key for hub chain transactions
 *   - HUB_ITRY_ADAPTER: Address of iTryTokenOFTAdapter on hub (from 12_DeployCrossChain)
 *   - HUB_SHARE_ADAPTER: Address of wiTryOFTAdapter on hub (from 12_DeployCrossChain)
 *   - SPOKE_ITRY_OFT: Address of iTryTokenOFT on spoke (from 20_DeploySpoke)
 *   - SPOKE_SHARE_OFT: Address of wiTryOFT on spoke (from 20_DeploySpoke)
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain
 */
contract ConfigurePeers is Script {
    // Default LayerZero EIDs
    uint32 internal constant OP_SEPOLIA_EID = 40232;
    uint32 internal constant ARB_SEPOLIA_EID = 40231;
    uint32 internal constant BASE_SEPOLIA_EID = 40245;

    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;

    struct PeerConfig {
        address hubITryAdapter;
        address hubShareAdapter;
        address spokeITryOFT;
        address spokeShareOFT;
        uint32 spokeEid;
    }

    function run() public {
        console2.log("=========================================");
        console2.log("30_ConfigurePeers: Hub->Spoke Configuration");
        console2.log("=========================================");
        console2.log("");

        // Load deployer key
        _loadDeployerKey();

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

    function _loadDeployerKey() internal {
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
    }

    function _loadConfig() internal view returns (PeerConfig memory config) {
        // Load from environment variables
        config.hubITryAdapter = vm.envOr("HUB_ITRY_ADAPTER", address(0));
        config.hubShareAdapter = vm.envOr("HUB_SHARE_ADAPTER", address(0));
        config.spokeITryOFT = vm.envOr("SPOKE_ITRY_OFT", address(0));
        config.spokeShareOFT = vm.envOr("SPOKE_SHARE_OFT", address(0));
        config.spokeEid = uint32(vm.envOr("SPOKE_CHAIN_EID", uint256(OP_SEPOLIA_EID)));

        // If not set, show helpful error
        if (config.hubITryAdapter == address(0)) {
            console2.log("ERROR: HUB_ITRY_ADAPTER not set");
            console2.log("Get this address from 12_DeployCrossChain output");
            revert("Missing HUB_ITRY_ADAPTER");
        }
        if (config.hubShareAdapter == address(0)) {
            console2.log("ERROR: HUB_SHARE_ADAPTER not set");
            console2.log("Get this address from 12_DeployCrossChain output");
            revert("Missing HUB_SHARE_ADAPTER");
        }
        if (config.spokeITryOFT == address(0)) {
            console2.log("ERROR: SPOKE_ITRY_OFT not set");
            console2.log("Get this address from 20_DeploySpoke output");
            revert("Missing SPOKE_ITRY_OFT");
        }
        if (config.spokeShareOFT == address(0)) {
            console2.log("ERROR: SPOKE_SHARE_OFT not set");
            console2.log("Get this address from 20_DeploySpoke output");
            revert("Missing SPOKE_SHARE_OFT");
        }
    }

    function _validateConfig(PeerConfig memory config) internal pure {
        require(config.hubITryAdapter != address(0), "Hub iTRY adapter is zero");
        require(config.hubShareAdapter != address(0), "Hub Share adapter is zero");
        require(config.spokeITryOFT != address(0), "Spoke iTRY OFT is zero");
        require(config.spokeShareOFT != address(0), "Spoke wiTRY OFT is zero");
        require(config.spokeEid != 0, "Spoke EID is zero");
    }

    function _displayConfig(PeerConfig memory config) internal view {
        console2.log("Hub Chain Configuration:");
        console2.log("  iTryTokenOFTAdapter:", config.hubITryAdapter);
        console2.log("  wiTryOFTAdapter (wiTRY):", config.hubShareAdapter);
        console2.log("");
        console2.log("Spoke Chain (EID:", config.spokeEid, "):");
        console2.log("  iTryTokenOFT:", config.spokeITryOFT);
        console2.log("  wiTryOFT:", config.spokeShareOFT);
        console2.log("");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", deployerAddress);
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
        console2.log("  iTryTokenOFTAdapter owner:", iTryAdapterOwner);
        console2.log("  wiTryOFTAdapter owner:", shareAdapterOwner);
        console2.log("  Current broadcaster:", deployerAddress);
        console2.log("");

        if (iTryAdapterOwner != deployerAddress) {
            console2.log("  [WARNING] Broadcaster is NOT owner of iTryTokenOFTAdapter!");
        }
        if (shareAdapterOwner != deployerAddress) {
            console2.log("  [WARNING] Broadcaster is NOT owner of wiTryOFTAdapter!");
        }
        console2.log("");

        // Configure iTryTokenOFTAdapter to recognize iTryTokenOFT on spoke chain
        bytes32 spokeITryPeer = bytes32(uint256(uint160(config.spokeITryOFT)));
        console2.log("Setting iTryTokenOFTAdapter peer...");
        console2.log("  Spoke EID:", config.spokeEid);
        console2.log("  Spoke iTRY OFT:", config.spokeITryOFT);

        IOAppCore(config.hubITryAdapter).setPeer(config.spokeEid, spokeITryPeer);
        console2.log("  [OK] iTryTokenOFTAdapter peer configured");
        console2.log("");

        // Configure wiTryOFTAdapter to recognize wiTryOFT on spoke chain
        bytes32 spokeSharePeer = bytes32(uint256(uint160(config.spokeShareOFT)));
        console2.log("Setting wiTryOFTAdapter peer...");
        console2.log("  Spoke EID:", config.spokeEid);
        console2.log("  Spoke wiTRY OFT:", config.spokeShareOFT);

        IOAppCore(config.hubShareAdapter).setPeer(config.spokeEid, spokeSharePeer);
        console2.log("  [OK] wiTryOFTAdapter peer configured");
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
        console2.log("  Hub:", config.hubITryAdapter);
        console2.log("  <->");
        console2.log("  Spoke (EID", config.spokeEid, "):", config.spokeITryOFT);
        console2.log("");
        console2.log("wiTRY Share Bridge:");
        console2.log("  Hub:", config.hubShareAdapter);
        console2.log("  <->");
        console2.log("  Spoke (EID", config.spokeEid, "):", config.spokeShareOFT);
        console2.log("");
        console2.log("=========================================");
        console2.log("NEXT STEPS:");
        console2.log("=========================================");
        console2.log("1. Set LayerZero libraries using 32_ConfigureLZLibraries.s.sol");
        console2.log("");
        console2.log("2. Verify deployments:");
        console2.log("   - Run 40_VerifyHub.s.sol on hub chain");
        console2.log("   - Run 41_VerifySpoke.s.sol on spoke chain");
        console2.log("");
        console2.log("3. Test cross-chain bridging using 42_VerifyBridge.s.sol");
        console2.log("=========================================");
    }
}
