// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IOracle} from "../../src/protocol/periphery/IOracle.sol";
import {DLFToken} from "../../src/external/DLFToken.sol";
import {iTry} from "../../src/token/iTRY/iTry.sol";
import {FastAccessVault} from "../../src/protocol/FastAccessVault.sol";
import {YieldForwarder} from "../../src/protocol/YieldForwarder.sol";
import {iTryIssuer} from "../../src/protocol/iTryIssuer.sol";
import {StakediTry} from "../../src/token/wiTRY/StakediTry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeploymentRegistry} from "./DeploymentRegistry.sol";
import {KeyDerivation} from "./KeyDerivation.sol";

/**
 * @title 40_VerifyHub
 * @notice [HUB] Verifies hub deployment and tests basic functionality
 * @dev Depends on: 10_DeployCore, 11_DeployProtocol
 * @dev Optional: 13_SetupTestnetState (for pre-populated testing)
 *
 * This script performs:
 * 1. Load and verify all deployed contract addresses
 * 2. Verify contract wiring and permissions
 * 3. Test basic minting functionality (if deployer is whitelisted)
 * 4. Test basic redemption functionality
 * 5. Display system state summary
 *
 * Key changes from v1 VerifyDeployment:
 * - Uses iTryIssuer instead of ControllerContract
 * - Uses FastAccessVault instead of BufferPool
 * - Uses StakediTry (ERC4626) instead of StakedUSDeV2
 * - Checks whitelist roles (new in v2)
 * - Verifies CREATE2 deployment addresses
 *
 * Run with:
 * forge script script/40_VerifyHub.s.sol --rpc-url <RPC>
 *
 * Or for full test with broadcasting:
 * forge script script/40_VerifyHub.s.sol --rpc-url <RPC> --broadcast
 */
contract VerifyHub is Script, DeploymentRegistry {
    uint256 internal constant WAD = 1e18;

    // Anvil default deployer key - only used for local testing (chainId 31337)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 internal deployerPrivateKey;
    address internal deployerAddress;
    KeyDerivation.ActorKeys internal actorKeys;

    bytes32 internal constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 internal constant WHITELISTED_USER_ROLE = keccak256("WHITELISTED_USER_ROLE");
    bytes32 internal constant MINTER_CONTRACT = keccak256("MINTER_CONTRACT");

    bool internal performTests = false;

    function run() public {
        _loadKeys();

        console2.log("=========================================");
        console2.log("40_VerifyHub: Hub Deployment Verification");
        console2.log("=========================================");
        console2.log("Network Chain ID:", block.chainid);
        console2.log("Deployer Address:", deployerAddress);
        console2.log("");

        // Load addresses from deployment registry
        require(registryExists(), "Deployment registry not found. Run deployment scripts first.");
        DeploymentAddresses memory addrs = loadAddresses();

        console2.log("Step 1: Loading deployment addresses...");
        _displayAddresses(addrs);
        console2.log("");

        console2.log("Step 2: Verifying contract existence...");
        _verifyContractCode(addrs);
        console2.log(unicode"  ✓ All contracts have code deployed");
        console2.log("");

        console2.log("Step 3: Verifying contract wiring...");
        _verifyWiring(addrs);
        console2.log(unicode"  ✓ All contracts properly wired");
        console2.log("");

        console2.log("Step 4: Verifying permissions and roles...");
        _verifyPermissions(addrs);
        console2.log(unicode"  ✓ All permissions correctly configured");
        console2.log("");

        console2.log("Step 5: Displaying system state...");
        _displaySystemState(addrs);
        console2.log("");

        // Check if deployer is whitelisted for testing
        iTryIssuer issuer = iTryIssuer(addrs.controller);
        performTests = issuer.hasRole(WHITELISTED_USER_ROLE, deployerAddress);

        if (performTests) {
            console2.log("Step 6: Testing mint and redeem functionality...");
            _testMintAndRedeem(addrs);
            console2.log("");
        } else {
            console2.log("Step 6: Skipping functional tests (deployer not whitelisted)");
            console2.log("  To enable tests: issuer.addToWhitelist(", deployerAddress, ")");
            console2.log("");
        }

        console2.log("=========================================");
        console2.log(unicode"✓ HUB VERIFICATION COMPLETE");
        console2.log("=========================================");
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("1. If using cross-chain: Run 12_DeployCrossChain.s.sol");
        console2.log("2. If using cross-chain: Run 20_DeploySpoke.s.sol on spoke chain");
        console2.log("3. If using cross-chain: Run 41_VerifySpoke.s.sol on spoke chain");
        console2.log("=========================================");
    }

    function _loadKeys() internal {
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

    function _displayAddresses(DeploymentAddresses memory addrs) internal view {
        console2.log("  Core Contracts:");
        console2.log("    Oracle:", addrs.oracle);
        console2.log("    DLF Token:", addrs.dlfToken);
        console2.log("    iTRY Token:", addrs.itryToken);
        console2.log("    Custodian:", addrs.custodian);
        console2.log("");
        console2.log("  Protocol Contracts:");
        console2.log("    iTryIssuer:", addrs.controller);
        console2.log("    FastAccessVault:", addrs.bufferPool);
        console2.log("    StakediTry:", addrs.staking);
        console2.log("    YieldForwarder:", addrs.yieldDistributor);
        console2.log("");
        console2.log("  Infrastructure:");
        console2.log("    CREATE2 Factory:", addrs.create2Factory);
    }

    function _verifyContractCode(DeploymentAddresses memory addrs) internal view {
        require(addrs.oracle.code.length > 0, "Oracle not deployed");
        require(addrs.dlfToken.code.length > 0, "DLF Token not deployed");
        require(addrs.itryToken.code.length > 0, "iTRY Token not deployed");
        require(addrs.controller.code.length > 0, "iTryIssuer not deployed");
        require(addrs.bufferPool.code.length > 0, "FastAccessVault not deployed");
        require(addrs.staking.code.length > 0, "StakediTry not deployed");
        require(addrs.yieldDistributor.code.length > 0, "YieldForwarder not deployed");
        require(addrs.create2Factory.code.length > 0, "CREATE2 Factory not deployed");

        // Custodian may or may not have code (could be EOA)
        if (addrs.custodian.code.length > 0) {
            console2.log("  Custodian is a contract");
        } else {
            console2.log("  Custodian is an EOA (externally owned account)");
        }
    }

    function _verifyWiring(DeploymentAddresses memory addrs) internal view {
        iTry itryToken = iTry(addrs.itryToken);
        iTryIssuer issuer = iTryIssuer(addrs.controller);
        FastAccessVault vault = FastAccessVault(addrs.bufferPool);
        StakediTry staking = StakediTry(addrs.staking);
        YieldForwarder yieldForwarder = YieldForwarder(addrs.yieldDistributor);

        // Verify iTryIssuer references
        console2.log("  Verifying iTryIssuer wiring...");
        require(address(issuer.iTryToken()) == addrs.itryToken, "iTryIssuer: wrong iTRY token");
        require(address(issuer.collateralToken()) == addrs.dlfToken, "iTryIssuer: wrong collateral token");
        require(address(issuer.oracle()) == addrs.oracle, "iTryIssuer: wrong oracle");
        require(address(issuer.liquidityVault()) == addrs.bufferPool, "iTryIssuer: wrong vault");
        require(issuer.custodian() == addrs.custodian, "iTryIssuer: wrong custodian");
        require(address(issuer.yieldReceiver()) == addrs.yieldDistributor, "iTryIssuer: wrong yield receiver");

        // Verify FastAccessVault wiring
        console2.log("  Verifying FastAccessVault wiring...");
        require(address(vault._vaultToken()) == addrs.dlfToken, "Vault: wrong vault token");
        require(address(vault._issuerContract()) == addrs.controller, "Vault: wrong issuer contract");
        require(vault.custodian() == addrs.custodian, "Vault: wrong custodian");

        // Verify iTRY token has issuer as minter
        console2.log("  Verifying iTRY token permissions...");
        require(itryToken.hasRole(MINTER_CONTRACT, addrs.controller), "iTRY: issuer not a minter");

        // Verify StakediTry references
        console2.log("  Verifying StakediTry wiring...");
        require(address(staking.asset()) == addrs.itryToken, "StakediTry: wrong asset");

        // Verify YieldForwarder wiring
        console2.log("  Verifying YieldForwarder wiring...");
        require(address(yieldForwarder.yieldToken()) == addrs.itryToken, "YieldForwarder: wrong yield token");
        require(yieldForwarder.yieldRecipient() != address(0), "YieldForwarder: no recipient set");
    }

    function _verifyPermissions(DeploymentAddresses memory addrs) internal view {
        StakediTry staking = StakediTry(addrs.staking);
        iTryIssuer issuer = iTryIssuer(addrs.controller);

        // Verify REWARDER_ROLE on StakediTry
        console2.log("  Verifying StakediTry roles...");
        require(staking.hasRole(REWARDER_ROLE, addrs.controller), "StakediTry: issuer missing REWARDER_ROLE");

        // Check if deployer still has REWARDER_ROLE (should be removed in production)
        if (staking.hasRole(REWARDER_ROLE, deployerAddress)) {
            console2.log("    WARNING: Deployer still has REWARDER_ROLE (should revoke in production)");
        }

        // Verify whitelist on iTryIssuer
        console2.log("  Verifying iTryIssuer whitelist...");
        if (issuer.hasRole(WHITELISTED_USER_ROLE, deployerAddress)) {
            console2.log("    Deployer is whitelisted for minting");
        } else {
            console2.log("    Deployer is NOT whitelisted (whitelist others before testing)");
        }
    }

    function _displaySystemState(DeploymentAddresses memory addrs) internal view {
        iTry itryToken = iTry(addrs.itryToken);
        DLFToken dlfToken = DLFToken(addrs.dlfToken);
        IOracle oracle = IOracle(addrs.oracle);
        FastAccessVault vault = FastAccessVault(addrs.bufferPool);
        StakediTry staking = StakediTry(addrs.staking);
        iTryIssuer issuer = iTryIssuer(addrs.controller);

        console2.log("  Oracle NAV Price:", oracle.price() / 1e18);
        console2.log("");

        console2.log("  iTRY Supply:");
        uint256 itrySupply = itryToken.totalSupply();
        console2.log("    Total Supply:", itrySupply / 1e18);
        console2.log("    Issued via Issuer:", issuer.getTotalIssuedITry() / 1e18);
        console2.log("");

        console2.log("  DLF Collateral:");
        uint256 totalCollateral = issuer.getCollateralUnderCustody();
        uint256 vaultBalance = dlfToken.balanceOf(addrs.bufferPool);
        uint256 custodianBalance = dlfToken.balanceOf(addrs.custodian);
        console2.log("    Total Under Custody:", totalCollateral / 1e18);
        console2.log("    In Vault:", vaultBalance / 1e18);
        console2.log("    At Custodian:", custodianBalance / 1e18);
        console2.log("");

        console2.log("  Staking:");
        uint256 stakedAssets = staking.totalAssets();
        uint256 stakedShares = staking.totalSupply();
        console2.log("    Total Assets (iTRY):", stakedAssets / 1e18);
        console2.log("    Total Shares (wiTRY):", stakedShares / 1e18);
        console2.log("");

        console2.log("  Vault Configuration:");
        console2.log("    Target Buffer %:", vault.targetBufferPercentageBPS(), "BPS");
        console2.log("    Minimum Balance:", vault.minimumExpectedBalance() / 1e18);
    }

    function _testMintAndRedeem(DeploymentAddresses memory addrs) internal {
        DLFToken dlfToken = DLFToken(addrs.dlfToken);
        iTry itryToken = iTry(addrs.itryToken);
        iTryIssuer issuer = iTryIssuer(addrs.controller);

        uint256 testAmount = 100e18; // 100 DLF

        // Check deployer's initial balances
        uint256 initialDlf = dlfToken.balanceOf(deployerAddress);
        uint256 initialItry = itryToken.balanceOf(deployerAddress);

        console2.log("  Deployer initial balances:");
        console2.log("    DLF:", initialDlf / 1e18);
        console2.log("    iTRY:", initialItry / 1e18);
        console2.log("");

        if (initialDlf < testAmount) {
            console2.log("  WARNING: Deployer has insufficient DLF for test");
            console2.log("  Minting test DLF to deployer...");

            vm.startBroadcast(deployerPrivateKey);
            dlfToken.mint(deployerAddress, testAmount);
            vm.stopBroadcast();

            console2.log(unicode"    ✓ Minted", testAmount / 1e18, "DLF for testing");
            console2.log("");
        }

        vm.startBroadcast(deployerPrivateKey);

        // Test minting iTRY
        console2.log("  Testing mint...");
        dlfToken.approve(address(issuer), testAmount);
        uint256 mintedItry = issuer.mintITRY(testAmount, 0);
        console2.log(unicode"    ✓ Minted iTRY:", mintedItry / 1e18);

        // Verify balance increased
        uint256 newItryBalance = itryToken.balanceOf(deployerAddress);
        require(newItryBalance >= initialItry + mintedItry, "iTRY balance mismatch");
        console2.log("    iTRY balance after mint:", newItryBalance / 1e18);
        console2.log("");

        // Test redeeming iTRY
        console2.log("  Testing redeem...");
        uint256 redeemAmount = mintedItry / 2; // Redeem half
        uint256 dlfBeforeRedeem = dlfToken.balanceOf(deployerAddress);

        itryToken.approve(address(issuer), redeemAmount);
        bool fromBuffer = issuer.redeemITRY(redeemAmount, 0);

        uint256 dlfAfterRedeem = dlfToken.balanceOf(deployerAddress);
        uint256 redeemedDlf = dlfAfterRedeem - dlfBeforeRedeem;

        console2.log("    Redeemed from buffer:", fromBuffer);
        console2.log(unicode"    ✓ Redeemed DLF:", redeemedDlf / 1e18);

        // Verify balances
        uint256 finalItry = itryToken.balanceOf(deployerAddress);
        uint256 finalDlf = dlfToken.balanceOf(deployerAddress);
        console2.log("    Final iTRY balance:", finalItry / 1e18);
        console2.log("    Final DLF balance:", finalDlf / 1e18);

        vm.stopBroadcast();

        console2.log(unicode"  ✓ Mint and redeem test successful!");
    }
}
