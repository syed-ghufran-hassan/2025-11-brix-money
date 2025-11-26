// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {iTryTokenOFTAdapter} from "../../src/token/iTRY/crosschain/iTryTokenOFTAdapter.sol";
import {wiTryOFTAdapter} from "../../src/token/wiTRY/crosschain/wiTryOFTAdapter.sol";
import {wiTryVaultComposer} from "../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {DeploymentRegistry} from "./DeploymentRegistry.sol";

/**
 * @title 12_DeployCrossChain
 * @notice [HUB] Deploys CrossChain infrastructure: iTRY OFT Adapter, wiTRY OFT Adapter, wiTryVaultComposer
 * @dev Depends on: 10_DeployCore, 11_DeployProtocol
 * @dev WARNING: Slow compilation due to LayerZero imports
 *
 * Key changes from v1:
 * - iTryTokenOFTAdapter instead of iTryTokenAdapter (v2 naming)
 * - wiTryOFTAdapter for wiTRY shares (from wiTryOFTAdapter.sol)
 * - wiTryVaultComposer for deposit-only composability (from wiTryVaultComposer.sol)
 *
 * Deployment sequence: 10 → 11 → 12
 * Next steps: 20_DeploySpoke → 30_ConfigurePeers → 32_ConfigureLZLibraries
 */
contract DeployCrossChain is Script, DeploymentRegistry {
    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;

    // LayerZero Endpoint addresses and EIDs (from LayerZeroDeploymentsRegistry.json)
    address internal constant ETHEREUM_MAINNET_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    uint32 internal constant ETHEREUM_MAINNET_EID = 30101;
    // Sepolia testnet endpoint (EID 40161)
    address internal constant SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    uint32 internal constant SEPOLIA_EID = 40161;

    bytes32 internal constant ITRY_ADAPTER_SALT = keccak256("itry.adapter.v2");
    bytes32 internal constant SHARE_ADAPTER_SALT = keccak256("itry.share.adapter.v2");
    bytes32 internal constant VAULT_COMPOSER_SALT = keccak256("itry.vault.composer.v2");

    function run() public {
        console2.log("=========================================");
        console2.log("12_DeployCrossChain: Starting CrossChain Deployment (v2)");
        console2.log("=========================================");

        // Load deployer key from environment with Anvil fallback
        _loadDeployerKey();

        console2.log("Deployer Address:", deployerAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // Load existing addresses from registry
        require(registryExists(), "Core/Protocol contracts not deployed. Run 10 and 11 first.");
        DeploymentAddresses memory addrs = loadAddresses();

        require(addrs.itryToken != address(0), "iTRY Token not deployed");
        require(addrs.staking != address(0), "Staking not deployed");

        console2.log("Loaded addresses:");
        console2.log("  iTRY Token:", addrs.itryToken);
        console2.log("  Staking (wiTRY):", addrs.staking);
        console2.log("");

        // Determine endpoint based on chain ID
        address endpoint = block.chainid == 1 ? ETHEREUM_MAINNET_ENDPOINT : SEPOLIA_ENDPOINT;
        console2.log("Using LayerZero endpoint:", endpoint);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        Create2Factory factory = Create2Factory(addrs.create2Factory);

        // Deploy CrossChain contracts
        iTryTokenOFTAdapter itryAdapter = _deployITryAdapter(factory, addrs.itryToken, endpoint);
        wiTryOFTAdapter shareAdapter = _deployShareAdapter(factory, addrs.staking, endpoint);
        wiTryVaultComposer wiTryVaultComposer =
            _deployVaultComposer(factory, addrs.staking, address(itryAdapter), address(shareAdapter));

        vm.stopBroadcast();

        // Update registry with CrossChain addresses
        addrs.itryAdapter = address(itryAdapter);
        addrs.shareAdapter = address(shareAdapter);
        addrs.wiTryVaultComposer = address(wiTryVaultComposer);

        saveAddresses(addrs);

        console2.log("=========================================");
        console2.log("CrossChain deployment complete!");
        console2.log("ITRY_OFT_ADAPTER:", address(itryAdapter));
        console2.log("WITRY_OFT_ADAPTER:", address(shareAdapter));
        console2.log("VAULT_COMPOSER:", address(wiTryVaultComposer));
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Deploy spoke chain contracts using 20_DeploySpoke.s.sol");
        console2.log("2. Configure peers bidirectionally using 30_ConfigurePeers.s.sol");
        console2.log("3. Set LayerZero libraries using 32_ConfigureLZLibraries.s.sol");
        console2.log("=========================================");
    }

    function _deployITryAdapter(Create2Factory factory, address itryToken, address endpoint)
        internal
        returns (iTryTokenOFTAdapter)
    {
        return iTryTokenOFTAdapter(
            _deployDeterministic(
                factory,
                abi.encodePacked(
                    type(iTryTokenOFTAdapter).creationCode, abi.encode(itryToken, endpoint, deployerAddress)
                ),
                ITRY_ADAPTER_SALT,
                "iTryTokenOFTAdapter"
            )
        );
    }

    function _deployShareAdapter(Create2Factory factory, address staking, address endpoint)
        internal
        returns (wiTryOFTAdapter)
    {
        return wiTryOFTAdapter(
            _deployDeterministic(
                factory,
                abi.encodePacked(type(wiTryOFTAdapter).creationCode, abi.encode(staking, endpoint, deployerAddress)),
                SHARE_ADAPTER_SALT,
                "wiTryOFTAdapter (wiTRY)"
            )
        );
    }

    function _deployVaultComposer(Create2Factory factory, address staking, address itryAdapter, address shareAdapter)
        internal
        returns (wiTryVaultComposer)
    {
        return wiTryVaultComposer(
            payable(_deployDeterministic(
                    factory,
                    abi.encodePacked(
                        type(wiTryVaultComposer).creationCode, abi.encode(staking, itryAdapter, shareAdapter)
                    ),
                    VAULT_COMPOSER_SALT,
                    "wiTryVaultComposer"
                ))
        );
    }

    function _deployDeterministic(Create2Factory factory, bytes memory bytecode, bytes32 salt, string memory label)
        internal
        returns (address deployed)
    {
        address predicted = _computeCreate2Address(address(factory), salt, keccak256(bytecode));
        deployed = factory.deploy(bytecode, salt, deployerAddress);
        require(deployed == predicted, "CREATE2 address mismatch");
        console2.log(label, "deployed:", deployed);
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 bytecodeHash)
        internal
        pure
        returns (address)
    {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)))));
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
}

interface Create2Factory {
    function deploy(bytes memory bytecode, bytes32 salt, address owner) external returns (address addr);
}
