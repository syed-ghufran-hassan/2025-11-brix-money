// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {FastAccessVault} from "../../src/protocol/FastAccessVault.sol";
import {YieldForwarder} from "../../src/protocol/YieldForwarder.sol";
import {iTryIssuer} from "../../src/protocol/iTryIssuer.sol";
import {StakediTry} from "../../src/token/wiTRY/StakediTry.sol";
import {iTry} from "../../src/token/iTRY/iTry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploymentRegistry} from "./DeploymentRegistry.sol";
import {KeyDerivation} from "./KeyDerivation.sol";

/**
 * @title 11_DeployProtocol
 * @notice [HUB] Deploys protocol layer for contracts-v2: FastAccessVault, YieldForwarder, iTryIssuer, StakediTry
 * @dev Depends on: 10_DeployCore (needs DLF, iTry, Oracle, Custodian addresses)
 *
 * Key changes from v1:
 * - FastAccessVault instead of BufferPool
 * - YieldForwarder (treasury only) instead of YieldDistributor (4 actors)
 * - iTryIssuer instead of ControllerContract
 * - StakediTry (ERC4626) instead of StakedUSDeV2
 * - Pre-computes addresses to solve chicken-egg dependency (FastAccessVault needs iTryIssuer address)
 *
 * Deployment sequence: 10 → 11 → 12
 */
contract DeployProtocol is Script, DeploymentRegistry {
    uint256 internal constant BASIS_POINTS = 10_000;
    uint256 internal constant BUFFER_TARGET_BPS = 500;
    uint256 internal constant MINIMUM_BUFFER_BALANCE = 0;

    // Anvil default keys - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables - loaded from environment or Anvil defaults
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;
    address internal treasuryAddress;
    address internal custodianAddress;

    bytes32 internal constant STAKING_SALT = keccak256("itry.staking.v2");
    bytes32 internal constant YIELD_FORWARDER_SALT = keccak256("itry.yield.forwarder.v2");
    bytes32 internal constant VAULT_SALT = keccak256("itry.vault.v2");
    bytes32 internal constant ISSUER_SALT = keccak256("itry.issuer.v2");

    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");

    function run() public {
        console2.log("=========================================");
        console2.log("11_DeployProtocol: Starting Protocol Deployment (v2)");
        console2.log("=========================================");

        // Load deployer key and derive actor addresses
        _loadKeys();

        console2.log("Deployer Address:", deployerAddress);
        console2.log("Treasury Address:", treasuryAddress);
        console2.log("Custodian Address:", custodianAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // Load core addresses from registry
        require(registryExists(), "Core contracts not deployed. Run 10_DeployCore first.");
        DeploymentAddresses memory addrs = loadAddresses();

        console2.log("Loaded core addresses:");
        console2.log("  DLF Token:", addrs.dlfToken);
        console2.log("  iTRY Token:", addrs.itryToken);
        console2.log("  Oracle:", addrs.oracle);
        console2.log("  Custodian:", addrs.custodian);
        console2.log("");

        // Phase 1: Pre-compute addresses (non-circular dependencies only)
        console2.log("Phase 1: Pre-computing addresses...");
        Create2Factory factory = Create2Factory(addrs.create2Factory);

        address predictedStaking = _predictContractAddress(factory, STAKING_SALT, _getStakingBytecode(addrs.itryToken));
        address predictedYieldForwarder =
            _predictContractAddress(factory, YIELD_FORWARDER_SALT, _getYieldForwarderBytecode(addrs.itryToken));

        // Issuer now deploys vault internally, so we only predict issuer
        address predictedIssuer = _predictContractAddress(
            factory, ISSUER_SALT, _getIssuerBytecode(addrs, predictedStaking, predictedYieldForwarder)
        );

        console2.log("Predicted addresses:");
        console2.log("  StakediTry:", predictedStaking);
        console2.log("  YieldForwarder:", predictedYieldForwarder);
        console2.log("  iTryIssuer:", predictedIssuer);
        console2.log("");

        // Phase 2: Deploy contracts
        console2.log("Phase 2: Deploying contracts...");
        vm.startBroadcast(deployerPrivateKey);

        StakediTry staking = _deployStaking(factory, addrs.itryToken);
        require(address(staking) == predictedStaking, "Staking address mismatch");

        YieldForwarder yieldForwarder = _deployYieldForwarder(factory, addrs.itryToken);
        require(address(yieldForwarder) == predictedYieldForwarder, "YieldForwarder address mismatch");

        // Deploy issuer (which internally deploys FastAccessVault)
        iTryIssuer issuer = _deployIssuer(factory, addrs, address(staking), address(yieldForwarder));
        require(address(issuer) == predictedIssuer, "Issuer address mismatch");

        // Get vault address from issuer
        FastAccessVault vault = FastAccessVault(address(issuer.liquidityVault()));

        console2.log("");
        console2.log("Phase 3: Wiring contracts...");
        console2.log("  FastAccessVault deployed by iTryIssuer at:", address(vault));

        // Grant MINTER_CONTRACT role to iTryIssuer on iTry
        iTry itry = iTry(addrs.itryToken);
        itry.addMinter(address(issuer));
        console2.log("  Granted MINTER_CONTRACT role to iTryIssuer");

        // Grant REWARDER_ROLE to iTryIssuer on StakediTry
        staking.grantRole(REWARDER_ROLE, address(issuer));
        console2.log("  Granted REWARDER_ROLE to iTryIssuer on StakediTry");

        // Whitelist deployer for testing
        issuer.addToWhitelist(deployerAddress);
        console2.log("  Whitelisted deployer on iTryIssuer");

        vm.stopBroadcast();

        // Update registry with new addresses
        addrs.staking = address(staking);
        addrs.yieldDistributor = address(yieldForwarder);
        addrs.bufferPool = address(vault);
        addrs.controller = address(issuer);

        saveAddresses(addrs);

        console2.log("=========================================");
        console2.log("Protocol deployment complete!");
        console2.log("STAKED_ITRY:", address(staking));
        console2.log("YIELD_FORWARDER:", address(yieldForwarder));
        console2.log("FAST_ACCESS_VAULT:", address(vault));
        console2.log("ITRY_ISSUER:", address(issuer));
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Whitelist users: issuer.addToWhitelist(address)");
        console2.log("2. Test minting: issuer.mintITRY(dlfAmount, minAmountOut)");
        console2.log("3. Test redemption: issuer.redeemITRY(itryAmount, minAmountOut)");
        console2.log("=========================================");
    }

    function _deployStaking(Create2Factory factory, address itryToken) internal returns (StakediTry) {
        return StakediTry(_deployDeterministic(factory, _getStakingBytecode(itryToken), STAKING_SALT, "StakediTry"));
    }

    function _deployYieldForwarder(Create2Factory factory, address itryToken) internal returns (YieldForwarder) {
        return YieldForwarder(
            _deployDeterministic(factory, _getYieldForwarderBytecode(itryToken), YIELD_FORWARDER_SALT, "YieldForwarder")
        );
    }

    function _deployIssuer(
        Create2Factory factory,
        DeploymentAddresses memory addrs,
        address staking,
        address yieldForwarder
    ) internal returns (iTryIssuer) {
        return iTryIssuer(
            _deployDeterministic(factory, _getIssuerBytecode(addrs, staking, yieldForwarder), ISSUER_SALT, "iTryIssuer")
        );
    }

    // Bytecode generation functions for CREATE2 prediction
    function _getStakingBytecode(address itryToken) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(StakediTry).creationCode,
            abi.encode(
                IERC20(itryToken), // asset
                deployerAddress, // initialRewarder (temporary)
                deployerAddress // owner
            )
        );
    }

    function _getYieldForwarderBytecode(address itryToken) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(YieldForwarder).creationCode,
            abi.encode(
                itryToken, // yieldToken
                treasuryAddress // initialRecipient
            )
        );
    }

    function _getIssuerBytecode(DeploymentAddresses memory addrs, address staking, address yieldForwarder)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            type(iTryIssuer).creationCode,
            abi.encode(
                addrs.itryToken, // _iTryToken
                addrs.dlfToken, // _collateralToken
                addrs.oracle, // _oracle
                treasuryAddress, // _treasury
                yieldForwarder, // _yieldReceiver
                custodianAddress, // _custodian
                deployerAddress, // _initialAdmin
                0, // _initialIssued (fresh deploy)
                0, // _initialDLFUnderCustody (fresh deploy)
                BUFFER_TARGET_BPS, // _vaultTargetPercentageBPS (5%)
                MINIMUM_BUFFER_BALANCE // _vaultMinimumBalance
            )
        );
    }

    function _predictContractAddress(Create2Factory factory, bytes32 salt, bytes memory bytecode)
        internal
        view
        returns (address)
    {
        return _computeCreate2Address(address(factory), salt, keccak256(bytecode));
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

    function _loadKeys() internal {
        // Use Anvil defaults for local testing (chainId 31337)
        // Otherwise derive all keys from DEPLOYER_PRIVATE_KEY
        if (block.chainid == 31337) {
            deployerPrivateKey = ANVIL_DEPLOYER_KEY;
            deployerAddress = vm.addr(ANVIL_DEPLOYER_KEY);
            console2.log("Using Anvil default keys for local testing");
        } else {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            console2.log("Using derived keys from DEPLOYER_PRIVATE_KEY");
        }

        // Get all actor keys
        KeyDerivation.ActorKeys memory keys = KeyDerivation.getActorKeys(vm, deployerPrivateKey);

        deployerAddress = vm.addr(keys.deployer);
        treasuryAddress = vm.addr(keys.treasury);
        custodianAddress = vm.addr(keys.custodian);
    }
}

interface Create2Factory {
    function deploy(bytes memory bytecode, bytes32 salt, address owner) external returns (address addr);
}
