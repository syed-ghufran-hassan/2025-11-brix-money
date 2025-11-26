// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {RedstoneNAVFeed} from "../../src/protocol/RedstoneNAVFeed.sol";
import {DLFToken} from "../../src/external/DLFToken.sol";
import {iTry} from "../../src/token/iTRY/iTry.sol";
import {DeploymentRegistry} from "./DeploymentRegistry.sol";
import {KeyDerivation} from "./KeyDerivation.sol";

/**
 * @title 10_DeployCore
 * @notice [HUB] Deploys core infrastructure for contracts-v2: Oracle, DLF, iTry (upgradeable), Custodian address
 * @dev Fast compilation - no LayerZero or complex dependencies
 *
 * Key changes from v1:
 * - RedstoneNAVFeed instead of MockDLFOracle
 * - iTry (upgradeable) with ERC1967Proxy instead of basic iTryToken
 * - Custodian is just an address (no contract)
 *
 * Deployment sequence: 10 → 11 → 12
 */
contract DeployCore is Script, DeploymentRegistry {
    uint256 internal constant NAV_PRICE = 20e18;
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;
    address internal custodianAddress;

    bytes32 internal constant CREATE2_FACTORY_SALT = keccak256("itry.factory.v2");
    bytes32 internal constant ORACLE_SALT = keccak256("itry.oracle.v2");
    bytes32 internal constant DLF_TOKEN_SALT = keccak256("itry.dlf.v2");
    bytes32 internal constant ITRY_IMPL_SALT = keccak256("itry.token.impl.v2");
    bytes32 internal constant ITRY_PROXY_SALT = keccak256("itry.token.proxy.v2");

    function run() public {
        console2.log("========================================");
        console2.log("10_DeployCore: Starting Core Deployment (v2)");
        console2.log("========================================");

        // Load deployer key from environment with Anvil fallback for local testing
        _loadDeployerKey();

        console2.log("Deployer Address:", deployerAddress);
        console2.log("Custodian Address:", custodianAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CREATE2 factory
        Create2Factory factory = _deployCreate2Factory();

        // Deploy core contracts
        RedstoneNAVFeed oracle = _deployOracle(factory);
        DLFToken dlfToken = _deployDLFToken(factory);

        // Deploy iTry with proxy (upgradeable pattern)
        (iTry itryImplementation, ERC1967Proxy itryProxy) = _deployITry(factory);
        address itryToken = address(itryProxy);

        vm.stopBroadcast();

        // Save addresses to registry
        DeploymentAddresses memory addrs = DeploymentAddresses({
            create2Factory: address(factory),
            oracle: address(oracle),
            dlfToken: address(dlfToken),
            itryToken: itryToken,
            custodian: custodianAddress,
            bufferPool: address(0),
            staking: address(0),
            yieldDistributor: address(0),
            controller: address(0),
            itryAdapter: address(0),
            shareAdapter: address(0),
            wiTryVaultComposer: address(0)
        });

        saveAddresses(addrs);

        console2.log("========================================");
        console2.log("Core deployment complete!");
        console2.log("CREATE2_FACTORY:", address(factory));
        console2.log("ORACLE:", address(oracle));
        console2.log("DLF_TOKEN:", address(dlfToken));
        console2.log("ITRY_IMPLEMENTATION:", address(itryImplementation));
        console2.log("ITRY_TOKEN (PROXY):", itryToken);
        console2.log("CUSTODIAN:", custodianAddress);
        console2.log("========================================");
    }

    function _deployCreate2Factory() internal returns (Create2Factory factory) {
        bytes32 bytecodeHash = keccak256(type(Create2Factory).creationCode);
        address predicted = _computeCreate2Address(CREATE2_DEPLOYER, CREATE2_FACTORY_SALT, bytecodeHash);

        if (predicted.code.length > 0) {
            console2.log("ERROR: Factory already exists at:", predicted);
            revert("Factory already deployed. Reset network or use existing deployment.");
        }

        factory = new Create2Factory{salt: CREATE2_FACTORY_SALT}();
        require(address(factory) == predicted, "Factory address mismatch");
        console2.log("Create2Factory deployed:", address(factory));
    }

    function _deployOracle(Create2Factory factory) internal returns (RedstoneNAVFeed) {
        // RedstoneNAVFeed has no constructor params (unlike old MockDLFOracle)
        return RedstoneNAVFeed(
            _deployDeterministic(factory, type(RedstoneNAVFeed).creationCode, ORACLE_SALT, "RedstoneNAVFeed")
        );
    }

    function _deployDLFToken(Create2Factory factory) internal returns (DLFToken) {
        return DLFToken(
            _deployDeterministic(
                factory,
                abi.encodePacked(type(DLFToken).creationCode, abi.encode(deployerAddress)),
                DLF_TOKEN_SALT,
                "DLFToken"
            )
        );
    }

    function _deployITry(Create2Factory factory) internal returns (iTry implementation, ERC1967Proxy proxy) {
        // Step 1: Deploy implementation
        implementation =
            iTry(_deployDeterministic(factory, type(iTry).creationCode, ITRY_IMPL_SALT, "iTry Implementation"));

        // Step 2: Prepare initialization data
        // iTry.initialize(address admin, address minterContract)
        // We use deployerAddress as initial minter, will be replaced by iTryIssuer in 11_DeployProtocol
        bytes memory initData = abi.encodeWithSelector(
            iTry.initialize.selector,
            deployerAddress, // admin
            deployerAddress // minterContract (temporary, will add iTryIssuer later)
        );

        // Step 3: Deploy proxy
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(implementation), initData));

        proxy = ERC1967Proxy(payable(_deployDeterministic(factory, proxyBytecode, ITRY_PROXY_SALT, "iTry Proxy")));

        console2.log("iTry initialized with admin:", deployerAddress);
        console2.log("iTry initialized with temporary minter:", deployerAddress);
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

        // Load actor keys to get custodian address
        KeyDerivation.ActorKeys memory actorKeys = KeyDerivation.getActorKeys(vm, deployerPrivateKey);
        custodianAddress = vm.addr(actorKeys.custodian);
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
}

interface IOwnableLike {
    function transferOwnership(address newOwner) external;
}

contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt, address indexed owner);

    function deploy(bytes memory bytecode, bytes32 salt, address owner) external returns (address addr) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        address predictedAddress = address(uint160(uint256(hash)));

        if (predictedAddress.code.length > 0) {
            revert("Create2Factory: Contract already exists at this address");
        }

        assembly {
            addr := create2(callvalue(), add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2Factory: deploy failed");

        if (owner != address(0)) {
            (bool success,) = addr.call(abi.encodeWithSelector(IOwnableLike.transferOwnership.selector, owner));
            success;
        }

        emit Deployed(addr, salt, owner);
    }
}
