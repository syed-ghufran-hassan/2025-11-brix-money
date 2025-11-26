// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {iTry} from "../../../src/token/iTRY/iTry.sol";
import {DLFToken} from "../../../src/external/DLFToken.sol";
import {FastAccessVault} from "../../../src/protocol/FastAccessVault.sol";
import {YieldForwarder} from "../../../src/protocol/YieldForwarder.sol";
import {iTryIssuer} from "../../../src/protocol/iTryIssuer.sol";
import {StakediTryCrosschain} from "../../../src/token/wiTRY/StakediTryCrosschain.sol";
import {IOracle} from "../../../src/protocol/periphery/IOracle.sol";
import {RedstoneNAVFeed} from "../../../src/protocol/RedstoneNAVFeed.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploymentRegistry} from "../DeploymentRegistry.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

/**
 * @title 04_SetupTestnetState
 * @notice [HUB] Sets up testnet state with pre-distributed tokens for testing
 * @dev Depends on: 01_DeployCore, 02_DeployProtocol
 * @dev Optional script - only for testnet environments where you want pre-populated accounts
 *
 * This script performs:
 * 0. Initialize oracle with NAV price
 * 1. Fund actors with ETH (if needed)
 * 2. Whitelist actors on iTryIssuer
 * 3. Distribute DLF collateral to all test actors
 * 4. Each actor mints iTRY tokens
 * 5. Stakers stake iTRY to get wiTRY shares
 * 6. Validate final system state
 *
 * Key changes from v1:
 * - Uses iTryIssuer instead of ControllerContract
 * - Uses StakediTryCrosschain (with COMPOSER_ROLE support) instead of StakedUSDeV2
 * - No YieldDistributor wiring (simplified to YieldForwarder → treasury only)
 * - No BufferPool rebalancing (FastAccessVault handles this automatically)
 * - Whitelist management required for minting
 *
 * Deployment sequence: 01 → 02 → 04 (optional) → 03
 */
contract SetupTestnetState is Script, DeploymentRegistry {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BASIS_POINTS = 10_000;

    // Token supply and pricing
    uint256 internal constant TOTAL_ITRY_SUPPLY = 829_074_000e18;
    uint256 internal constant NAV_PRICE = 20e18;
    uint256 internal constant MINTER_DLF_AMOUNT = 10_000e18;
    uint256 internal constant TOTAL_DLF_COLLATERAL = (TOTAL_ITRY_SUPPLY * WAD) / NAV_PRICE;

    // Percentage shares
    uint256 internal constant CEX_SHARE_BPS = 4_000;
    uint256 internal constant DEX_SHARE_BPS = 4_000;
    uint256 internal constant TREASURY_SHARE_BPS = 500;
    uint256 internal constant STAKER_CLUSTER_BPS = 1_470;
    uint256 internal constant SINGLE_STAKER_BPS = 490;
    uint256 internal constant REDEEMER_BPS = 30;

    // Target amounts per actor
    uint256 internal constant CEX_ITRY_TARGET = (TOTAL_ITRY_SUPPLY * CEX_SHARE_BPS) / BASIS_POINTS;
    uint256 internal constant DEX_ITRY_TARGET = (TOTAL_ITRY_SUPPLY * DEX_SHARE_BPS) / BASIS_POINTS;
    uint256 internal constant TREASURY_ITRY_TARGET = (TOTAL_ITRY_SUPPLY * TREASURY_SHARE_BPS) / BASIS_POINTS;
    uint256 internal constant STAKER_CLUSTER_ITRY = (TOTAL_ITRY_SUPPLY * STAKER_CLUSTER_BPS) / BASIS_POINTS;
    uint256 internal constant SINGLE_STAKER_ITRY = (TOTAL_ITRY_SUPPLY * SINGLE_STAKER_BPS) / BASIS_POINTS;
    uint256 internal constant REDEEMER_ITRY_TARGET = (TOTAL_ITRY_SUPPLY * REDEEMER_BPS) / BASIS_POINTS;

    uint256 internal constant CEX_DLF_REQUIRED = (CEX_ITRY_TARGET * WAD) / NAV_PRICE;
    uint256 internal constant DEX_DLF_REQUIRED = (DEX_ITRY_TARGET * WAD) / NAV_PRICE;
    uint256 internal constant TREASURY_DLF_REQUIRED = (TREASURY_ITRY_TARGET * WAD) / NAV_PRICE;
    uint256 internal constant SINGLE_STAKER_DLF_REQUIRED = (SINGLE_STAKER_ITRY * WAD) / NAV_PRICE;
    uint256 internal constant REDEEMER_DLF_REQUIRED = (REDEEMER_ITRY_TARGET * WAD) / NAV_PRICE;
    uint256 internal constant MINTER_DLF_REQUIRED = MINTER_DLF_AMOUNT;

    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Runtime variables
    uint256 internal deployerPrivateKey;
    address internal deployerAddress;
    KeyDerivation.ActorKeys internal actorKeys;

    bytes32 internal constant WHITELISTED_USER_ROLE = keccak256("WHITELISTED_USER_ROLE");

    struct ActorConfig {
        string name;
        uint256 privateKey;
        address addr;
        uint256 itryTarget;
        uint256 dlfDeposit;
        bool stake;
    }

    function run() public {
        console2.log("=========================================");
        console2.log("04_SetupTestnetState: Starting Testnet State Setup");
        console2.log("=========================================");

        // Load deployer key
        _loadDeployerKey();

        console2.log("Deployer Address:", deployerAddress);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        // Load deployed contracts
        require(registryExists(), "Contracts not deployed. Run 01 and 02 first.");
        DeploymentAddresses memory addrs = loadAddresses();

        // Verify required contracts are deployed
        _verifyDeployments(addrs);

        console2.log("Loaded contract addresses:");
        console2.log("  DLF Token:", addrs.dlfToken);
        console2.log("  iTRY Token:", addrs.itryToken);
        console2.log("  iTryIssuer:", addrs.controller);
        console2.log("  FastAccessVault:", addrs.bufferPool);
        console2.log("  StakediTryCrosschain:", addrs.staking);
        console2.log("  YieldForwarder:", addrs.yieldDistributor);
        console2.log("");

        // Build actor configs once
        ActorConfig[] memory actors = _actorConfigs();

        // INITIALIZE: Set oracle price
        console2.log("INITIALIZE: Setting oracle NAV price...");
        _initializeOracle(addrs);
        console2.log("");

        // PHASE 0: Fund actors with ETH (if on non-Anvil network)
        if (block.chainid != 31337) {
            console2.log("PHASE 0: Funding actor addresses with ETH...");
            _fundActors(actors);
            console2.log("");
        }

        // PHASE 1: Whitelist actors
        console2.log("PHASE 1: Whitelisting actors on iTryIssuer...");
        _whitelistActors(addrs, actors);
        console2.log("");

        // PHASE 2: Distribute DLF collateral
        console2.log("PHASE 2: Distributing DLF collateral to actors...");
        _distributeDLF(addrs, actors);
        console2.log("");

        // PHASE 3: Each actor mints iTRY and optionally stakes
        console2.log("PHASE 3: Actors minting iTRY and staking...");
        _mintAndStake(addrs, actors);
        console2.log("");

        // PHASE 4: Validate system
        console2.log("PHASE 4: Validating system state...");
        _validateSystem(addrs, actors);
        console2.log("");

        console2.log("=========================================");
        console2.log("Testnet state setup complete!");
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. Run 03_DeployCrossChain.s.sol to deploy crosschain infrastructure");
        console2.log("2. Verify deployment and test system");
        console2.log("=========================================");
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

        // Load all actor keys
        actorKeys = KeyDerivation.getActorKeys(vm, deployerPrivateKey);
    }

    function _verifyDeployments(DeploymentAddresses memory addrs) internal view {
        require(addrs.dlfToken != address(0), "DLF Token not deployed");
        require(addrs.itryToken != address(0), "iTRY Token not deployed");
        require(addrs.controller != address(0), "iTryIssuer not deployed");
        require(addrs.bufferPool != address(0), "FastAccessVault not deployed");
        require(addrs.staking != address(0), "StakediTryCrosschain not deployed");
        require(addrs.yieldDistributor != address(0), "YieldForwarder not deployed");
        require(addrs.custodian != address(0), "Custodian not set");
        require(addrs.oracle != address(0), "Oracle not deployed");
    }

    function _initializeOracle(DeploymentAddresses memory addrs) internal {
        RedstoneNAVFeed oracle = RedstoneNAVFeed(addrs.oracle);

        vm.startBroadcast(deployerPrivateKey);

        // Set the NAV price (20 TRY per DLF)
        oracle.setPrice(NAV_PRICE);
        console2.log(unicode"  ✓ Oracle price set to:", NAV_PRICE / 1e18, "TRY per DLF");

        vm.stopBroadcast();
    }

    function _fundActors(ActorConfig[] memory actors) internal {
        uint256 fundingAmount = 0.1 ether;

        vm.startBroadcast(deployerPrivateKey);

        console2.log("  Funding actors with 0.1 ETH each for gas...");
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 balance = actors[i].addr.balance;

            if (balance < fundingAmount) {
                uint256 needed = fundingAmount - balance;
                payable(actors[i].addr).transfer(needed);
                console2.log(unicode"    ✓", actors[i].name, "funded");
            } else {
                console2.log(unicode"    ✓", actors[i].name, "already has sufficient ETH");
            }
        }

        vm.stopBroadcast();

        console2.log(unicode"  ✓ All actors funded");
    }

    function _whitelistActors(DeploymentAddresses memory addrs, ActorConfig[] memory actors) internal {
        iTryIssuer issuer = iTryIssuer(addrs.controller);

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < actors.length; i++) {
            // Check if already whitelisted
            if (!issuer.hasRole(WHITELISTED_USER_ROLE, actors[i].addr)) {
                issuer.addToWhitelist(actors[i].addr);
                console2.log(unicode"    ✓", actors[i].name, "whitelisted");
            } else {
                console2.log(unicode"    ✓", actors[i].name, "already whitelisted");
            }
        }

        vm.stopBroadcast();

        console2.log(unicode"  ✓ All actors whitelisted");
    }

    function _distributeDLF(DeploymentAddresses memory addrs, ActorConfig[] memory actors) internal {
        DLFToken dlfToken = DLFToken(addrs.dlfToken);

        console2.log("  Minting DLF collateral to actors...");
        uint256 mintedDLF;
        vm.startBroadcast(deployerPrivateKey);
        for (uint256 i = 0; i < actors.length; i++) {
            dlfToken.mint(actors[i].addr, actors[i].dlfDeposit);
            mintedDLF += actors[i].dlfDeposit;
            console2.log(unicode"    ✓", actors[i].name, "received DLF:", actors[i].dlfDeposit / 1e18);
        }
        vm.stopBroadcast();

        require(mintedDLF == TOTAL_DLF_COLLATERAL + MINTER_DLF_REQUIRED, "DLF collateral mismatch");
        console2.log(unicode"  ✓ Total DLF minted:", mintedDLF / 1e18);
    }

    function _mintAndStake(DeploymentAddresses memory addrs, ActorConfig[] memory actors) internal {
        DLFToken dlfToken = DLFToken(addrs.dlfToken);
        iTry itryToken = iTry(addrs.itryToken);
        iTryIssuer issuer = iTryIssuer(addrs.controller);
        StakediTryCrosschain staking = StakediTryCrosschain(addrs.staking);

        console2.log("  Processing actor minting and staking...");
        for (uint256 i = 0; i < actors.length; i++) {
            vm.startBroadcast(actors[i].privateKey);

            // Mint iTRY if target > 0
            if (actors[i].itryTarget > 0) {
                // Approve DLF for minting
                dlfToken.approve(address(issuer), actors[i].dlfDeposit);

                // Mint iTRY (minAmountOut = 0 for testnet simplicity)
                uint256 mintedAmount = issuer.mintITRY(actors[i].dlfDeposit, 0);
                console2.log(unicode"    ✓", actors[i].name, "minted iTRY:", mintedAmount / 1e18);

                // Stake if this actor is a staker
                if (actors[i].stake) {
                    itryToken.approve(address(staking), mintedAmount);
                    uint256 shares = staking.deposit(mintedAmount, actors[i].addr);
                    console2.log(unicode"    ✓", actors[i].name, "staked wiTRY shares:", shares / 1e18);
                }
            } else {
                // Minter actor - just holds DLF
                console2.log(unicode"    ✓", actors[i].name, "holds DLF (no iTRY minted)");
            }

            vm.stopBroadcast();
        }

        console2.log(unicode"  ✓ Minting and staking complete");
    }

    function _validateSystem(DeploymentAddresses memory addrs, ActorConfig[] memory actors) internal view {
        iTry itryToken = iTry(addrs.itryToken);
        DLFToken dlfToken = DLFToken(addrs.dlfToken);
        IOracle oracle = IOracle(addrs.oracle);
        FastAccessVault vault = FastAccessVault(addrs.bufferPool);
        StakediTryCrosschain staking = StakediTryCrosschain(addrs.staking);
        iTryIssuer issuer = iTryIssuer(addrs.controller);

        console2.log("  Validating total supply...");
        uint256 actualSupply = itryToken.totalSupply();
        // Note: Actual supply may differ slightly due to fees
        console2.log("    Expected iTRY supply:", TOTAL_ITRY_SUPPLY / 1e18);
        console2.log("    Actual iTRY supply:", actualSupply / 1e18);

        console2.log("  Validating NAV price...");
        uint256 navPrice = oracle.price();
        console2.log("    NAV price:", navPrice / 1e18);
        require(navPrice > 0, "Invalid NAV price");

        console2.log("  Validating collateral...");
        uint256 totalCollateral = issuer.getCollateralUnderCustody();
        console2.log("    Total DLF under custody:", totalCollateral / 1e18);
        console2.log("    Expected:", TOTAL_DLF_COLLATERAL / 1e18);

        console2.log("  Validating vault...");
        uint256 vaultBalance = dlfToken.balanceOf(address(vault));
        console2.log("    Vault DLF balance:", vaultBalance / 1e18);

        console2.log("  Validating custodian...");
        uint256 custodianBalance = dlfToken.balanceOf(addrs.custodian);
        console2.log("    Custodian DLF balance:", custodianBalance / 1e18);

        address cexAddr = vm.addr(actorKeys.cex);
        address dexAddr = vm.addr(actorKeys.dex);
        address treasuryAddr = vm.addr(actorKeys.treasury);

        console2.log("  Validating actor balances...");
        console2.log("    CEX iTRY:", itryToken.balanceOf(cexAddr) / 1e18);
        console2.log("    DEX iTRY:", itryToken.balanceOf(dexAddr) / 1e18);
        console2.log("    Treasury iTRY:", itryToken.balanceOf(treasuryAddr) / 1e18);

        console2.log("  Validating staking...");
        uint256 stakedAssets = staking.totalAssets();
        console2.log("    Total staked iTRY:", stakedAssets / 1e18);
        console2.log("    Expected staked:", STAKER_CLUSTER_ITRY / 1e18);

        // Verify stakers have no residual iTRY (all staked)
        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i].stake) {
                uint256 residual = itryToken.balanceOf(actors[i].addr);
                if (residual > 0) {
                    console2.log("    WARNING:", actors[i].name, "has residual iTRY:", residual / 1e18);
                }
            }
        }

        console2.log(unicode"  ✓ Validation complete!");
        console2.log("");
        console2.log("System State Summary:");
        console2.log("  Total iTRY supply:", itryToken.totalSupply() / 1e18);
        console2.log("  Vault DLF:", vaultBalance / 1e18);
        console2.log("  Custodian DLF:", custodianBalance / 1e18);
        console2.log("  Staked iTRY:", stakedAssets / 1e18);
    }

    function _actorConfigs() internal view returns (ActorConfig[] memory configs) {
        configs = new ActorConfig[](8);
        configs[0] = ActorConfig({
            name: "Treasury",
            privateKey: actorKeys.treasury,
            addr: vm.addr(actorKeys.treasury),
            itryTarget: TREASURY_ITRY_TARGET,
            dlfDeposit: TREASURY_DLF_REQUIRED,
            stake: false
        });
        configs[1] = ActorConfig({
            name: "CEX Desk",
            privateKey: actorKeys.cex,
            addr: vm.addr(actorKeys.cex),
            itryTarget: CEX_ITRY_TARGET,
            dlfDeposit: CEX_DLF_REQUIRED,
            stake: false
        });
        configs[2] = ActorConfig({
            name: "DEX Desk",
            privateKey: actorKeys.dex,
            addr: vm.addr(actorKeys.dex),
            itryTarget: DEX_ITRY_TARGET,
            dlfDeposit: DEX_DLF_REQUIRED,
            stake: false
        });
        configs[3] = ActorConfig({
            name: "Staker A",
            privateKey: actorKeys.staker1,
            addr: vm.addr(actorKeys.staker1),
            itryTarget: SINGLE_STAKER_ITRY,
            dlfDeposit: SINGLE_STAKER_DLF_REQUIRED,
            stake: true
        });
        configs[4] = ActorConfig({
            name: "Staker B",
            privateKey: actorKeys.staker2,
            addr: vm.addr(actorKeys.staker2),
            itryTarget: SINGLE_STAKER_ITRY,
            dlfDeposit: SINGLE_STAKER_DLF_REQUIRED,
            stake: true
        });
        configs[5] = ActorConfig({
            name: "Staker C",
            privateKey: actorKeys.staker3,
            addr: vm.addr(actorKeys.staker3),
            itryTarget: SINGLE_STAKER_ITRY,
            dlfDeposit: SINGLE_STAKER_DLF_REQUIRED,
            stake: true
        });
        configs[6] = ActorConfig({
            name: "Minter",
            privateKey: actorKeys.minter,
            addr: vm.addr(actorKeys.minter),
            itryTarget: 0,
            dlfDeposit: MINTER_DLF_REQUIRED,
            stake: false
        });
        configs[7] = ActorConfig({
            name: "Redeemer",
            privateKey: actorKeys.redeemer,
            addr: vm.addr(actorKeys.redeemer),
            itryTarget: REDEEMER_ITRY_TARGET,
            dlfDeposit: REDEEMER_DLF_REQUIRED,
            stake: false
        });
    }
}
