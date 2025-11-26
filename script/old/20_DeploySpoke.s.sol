// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {iTryTokenOFT} from "../../src/token/iTRY/crosschain/iTryTokenOFT.sol";
import {wiTryOFT} from "../../src/token/wiTRY/crosschain/wiTryOFT.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";

/**
 * @title 20_DeploySpoke
 * @notice [SPOKE] Deployment script for iTRY spoke chain (L2) contracts
 * @dev This script deploys the OFT contracts on L2 chains (e.g., Optimism, Arbitrum, Base)
 *
 * Key changes from v1:
 * - ShareOFT → wiTryOFT (renamed to match wiTRY branding)
 * - wiTryOFT constructor requires name/symbol parameters
 * - Contract paths updated to v2 structure
 *
 * Deployment sequence: 10 → 11 → 12 (hub) then 20 (spoke)
 * Next steps: 30_ConfigurePeers → 32_ConfigureLZLibraries
 *
 * Usage:
 *   forge script script/20_DeploySpoke.s.sol:DeploySpoke \
 *     --rpc-url <L2_RPC_URL> \
 *     --broadcast \
 *     --verify
 *
 * Environment variables required:
 *   - DEPLOYER_PRIVATE_KEY: Private key for deploying on spoke chain
 *   - SPOKE_CHAIN_ENDPOINT: LayerZero endpoint address on spoke chain (optional, defaults to OP Sepolia)
 *   - HUB_CHAIN_EID: LayerZero endpoint ID for hub chain (optional, defaults to Sepolia)
 *   - HUB_ITRY_ADAPTER: Address of iTryTokenOFTAdapter on hub chain (required)
 *   - HUB_SHARE_ADAPTER: Address of wiTryOFTAdapter on hub chain (required)
 */
contract DeploySpoke is Script {
    // LayerZero Endpoint addresses per chain (from LayerZeroDeploymentsRegistry.json)
    // See: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts

    // Mainnet Endpoints
    address internal constant ETHEREUM_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant OPTIMISM_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant ARBITRUM_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant BASE_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant POLYGON_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;

    // Testnet Endpoints (from LayerZeroDeploymentsRegistry.json)
    // Sepolia testnet (EID 40161)
    address internal constant SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    // OP Sepolia testnet (EID 40232)
    address internal constant OP_SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant ARB_SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address internal constant BASE_SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // LayerZero Endpoint IDs (from LayerZeroDeploymentsRegistry.json)
    uint32 internal constant ETHEREUM_MAINNET_EID = 30101;
    uint32 internal constant OPTIMISM_MAINNET_EID = 30111;
    uint32 internal constant ARBITRUM_MAINNET_EID = 30110;
    uint32 internal constant BASE_MAINNET_EID = 30184;
    uint32 internal constant POLYGON_MAINNET_EID = 30109;

    // Testnet EIDs
    uint32 internal constant SEPOLIA_EID = 40161;
    uint32 internal constant OP_SEPOLIA_EID = 40232;
    uint32 internal constant ARB_SEPOLIA_EID = 40231;
    uint32 internal constant BASE_SEPOLIA_EID = 40245;

    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;

    struct SpokeDeploymentConfig {
        address endpoint;
        uint32 hubChainEid;
        address hubITryAdapter;
        address hubShareAdapter;
        address deployer;
    }

    struct DeployedContracts {
        iTryTokenOFT itryTokenOFT;
        wiTryOFT wiTryOFT;
    }

    DeployedContracts public deployed;

    function run() public {
        // Load configuration from environment
        SpokeDeploymentConfig memory config = _loadConfig();

        // Validate configuration
        _validateConfig(config);

        console2.log("=========================================");
        console2.log("20_DeploySpoke: Starting Spoke Chain Deployment (v2)");
        console2.log("=========================================");
        console2.log("Endpoint:", config.endpoint);
        console2.log("Hub Chain EID:", config.hubChainEid);
        console2.log("Hub iTRY Adapter:", config.hubITryAdapter);
        console2.log("Hub wiTRY Adapter:", config.hubShareAdapter);
        console2.log("Deployer:", config.deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("=========================================");
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        deployed = _deployContracts(config);

        // Configure peer relationships (spoke → hub)
        _configurePeers(config);

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary(config);
    }

    function _loadConfig() internal returns (SpokeDeploymentConfig memory config) {
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

        // Try to load from environment variables first
        address endpoint = vm.envOr("SPOKE_CHAIN_ENDPOINT", address(0));
        uint32 hubChainEid = uint32(vm.envOr("HUB_CHAIN_EID", uint256(0)));
        address hubITryAdapter = vm.envOr("HUB_ITRY_ADAPTER", address(0));
        address hubShareAdapter = vm.envOr("HUB_SHARE_ADAPTER", address(0));

        // If environment variables not set, use defaults for testnet
        if (endpoint == address(0)) {
            console2.log("WARNING: Using default testnet configuration");
            console2.log("Set SPOKE_CHAIN_ENDPOINT, HUB_CHAIN_EID, HUB_ITRY_ADAPTER, HUB_SHARE_ADAPTER for production");
            console2.log("");

            endpoint = OP_SEPOLIA_ENDPOINT;
            hubChainEid = SEPOLIA_EID;
            // These need to be set from hub deployment (12_DeployCrossChain)
            require(hubITryAdapter != address(0), "HUB_ITRY_ADAPTER must be set");
            require(hubShareAdapter != address(0), "HUB_SHARE_ADAPTER must be set");
        }

        config = SpokeDeploymentConfig({
            endpoint: endpoint,
            hubChainEid: hubChainEid,
            hubITryAdapter: hubITryAdapter,
            hubShareAdapter: hubShareAdapter,
            deployer: deployerAddress
        });
    }

    function _validateConfig(SpokeDeploymentConfig memory config) internal pure {
        require(config.endpoint != address(0), "Invalid endpoint address");
        require(config.hubChainEid != 0, "Invalid hub chain EID");
        require(config.hubITryAdapter != address(0), "Invalid hub iTRY adapter address");
        require(config.hubShareAdapter != address(0), "Invalid hub wiTRY adapter address");
        require(config.deployer != address(0), "Invalid deployer address");
    }

    function _deployContracts(SpokeDeploymentConfig memory config)
        internal
        returns (DeployedContracts memory contracts)
    {
        console2.log("=== Deploying Spoke Chain Contracts ===");
        console2.log("");

        // Deploy iTryTokenOFT (same constructor as v1)
        contracts.itryTokenOFT = new iTryTokenOFT(config.endpoint, config.deployer);
        console2.log("iTryTokenOFT deployed:", address(contracts.itryTokenOFT));

        // Deploy wiTryOFT (v2: requires name and symbol)
        contracts.wiTryOFT = new wiTryOFT(
            "Wrapped iTRY", // name
            "wiTRY", // symbol
            config.endpoint, // _lzEndpoint
            config.deployer // _delegate
        );
        console2.log("wiTryOFT deployed:", address(contracts.wiTryOFT));

        console2.log("");
        console2.log("=== Contracts Deployed Successfully ===");
        console2.log("");
    }

    function _configurePeers(SpokeDeploymentConfig memory config) internal {
        console2.log("=== Configuring Peer Relationships (Spoke -> Hub) ===");
        console2.log("");

        // Set iTryTokenOFT peer to hub chain's iTryTokenOFTAdapter
        IOAppCore(address(deployed.itryTokenOFT))
            .setPeer(config.hubChainEid, bytes32(uint256(uint160(config.hubITryAdapter))));
        console2.log("iTryTokenOFT peer set to hub iTryTokenOFTAdapter");

        // Set wiTryOFT peer to hub chain's wiTryOFTAdapter
        IOAppCore(address(deployed.wiTryOFT))
            .setPeer(config.hubChainEid, bytes32(uint256(uint160(config.hubShareAdapter))));
        console2.log("wiTryOFT peer set to hub wiTryOFTAdapter");

        console2.log("");
        console2.log("=== Peer Configuration Complete ===");
        console2.log("");
    }

    function _logDeploymentSummary(SpokeDeploymentConfig memory config) internal view {
        console2.log("=========================================");
        console2.log("SPOKE CHAIN DEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Spoke EID:", _getChainEid());
        console2.log("Endpoint:", config.endpoint);
        console2.log("");
        console2.log("Deployed Contracts:");
        console2.log("  iTryTokenOFT:", address(deployed.itryTokenOFT));
        console2.log("  wiTryOFT:", address(deployed.wiTryOFT));
        console2.log("");
        console2.log("Peer Configuration (Spoke -> Hub):");
        console2.log("  Hub Chain EID:", config.hubChainEid);
        console2.log("  Hub iTRY Adapter:", config.hubITryAdapter);
        console2.log("  Hub wiTRY Adapter:", config.hubShareAdapter);
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Configure hub chain peers using 30_ConfigurePeers.s.sol:");
        console2.log("   - Hub iTRY Adapter -> Spoke iTRY OFT");
        console2.log("   - Hub wiTRY Adapter -> Spoke wiTRY OFT");
        console2.log("");
        console2.log("2. Set LayerZero libraries using 32_ConfigureLZLibraries.s.sol");
        console2.log("");
        console2.log("Spoke Contract Addresses for Peer Configuration:");
        console2.log("  Spoke EID:", _getChainEid());
        console2.log("  iTryTokenOFT:", _toBytes32String(address(deployed.itryTokenOFT)));
        console2.log("  wiTryOFT:", _toBytes32String(address(deployed.wiTryOFT)));
        console2.log("=========================================");
    }

    function _getChainEid() internal view returns (uint32) {
        uint256 chainId = block.chainid;

        // Mainnet
        if (chainId == 1) return ETHEREUM_MAINNET_EID;
        if (chainId == 10) return OPTIMISM_MAINNET_EID;
        if (chainId == 42161) return ARBITRUM_MAINNET_EID;
        if (chainId == 8453) return BASE_MAINNET_EID;
        if (chainId == 137) return POLYGON_MAINNET_EID;

        // Testnet
        if (chainId == 11155111) return SEPOLIA_EID;
        if (chainId == 11155420) return OP_SEPOLIA_EID;
        if (chainId == 421614) return ARB_SEPOLIA_EID;
        if (chainId == 84532) return BASE_SEPOLIA_EID;

        revert("Unsupported chain ID");
    }

    function _toBytes32String(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }

    // Getter function for external access
    function getDeployedContracts() external view returns (address itryTokenOFT, address wiTryOFT) {
        return (address(deployed.itryTokenOFT), address(deployed.wiTryOFT));
    }
}
