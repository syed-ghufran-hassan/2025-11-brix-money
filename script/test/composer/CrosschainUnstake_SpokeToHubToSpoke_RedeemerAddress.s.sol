// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

/**
 * @notice UserCooldown structure matching StakediTryCrosschain
 */
struct UserCooldown {
    uint104 cooldownEnd;
    uint256 underlyingAmount;
}

/**
 * @notice Interface for UnstakeMessenger on spoke chain
 */
interface IUnstakeMessenger {
    function unstake(uint256 returnTripAllocation) external payable returns (bytes32 guid);
    function quoteUnstake() external view returns (uint256 nativeFee, uint256 lzTokenFee);
    function quoteUnstakeWithReturnValue(uint256 returnTripValue) external view returns (uint256 nativeFee, uint256 lzTokenFee);
    function hubEid() external view returns (uint32);
    function feeBufferBPS() external view returns (uint256);
}

/**
 * @notice Interface for wiTryVaultComposer on hub chain (quote function)
 */
interface IVaultComposer {
    function quoteUnstakeReturn(
        address to,
        uint256 amount,
        uint32 dstEid
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee);
}

/**
 * @notice Interface for StakediTryCrosschain on hub chain (cooldown queries only)
 */
interface IStakediTryCrosschain {
    function cooldowns(address user) external view returns (uint104 cooldownEnd, uint256 underlyingAmount);
}

/**
 * @title CrosschainUnstake_SpokeToHubToSpoke_RedeemerAddress
 * @notice Test script for complete crosschain unstaking flow: Spoke → Hub → Spoke
 * @dev This script demonstrates the full user journey after cooldown completion:
 *
 * Flow Overview:
 *   1. Setup: Verify user has completed cooldown on hub chain
 *   2. Quote: Get LayerZero fee for unstake operation
 *   3. Execute: Call unstake() on spoke chain
 *   4. Monitor: Track message via LayerZeroScan
 *   5. Verify: Check cooldown cleared on hub, iTRY received on spoke
 *
 * Prerequisites:
 *   - User must have completed cooldown period on hub chain
 *   - Cooldown verification: StakediTryCrosschain.cooldowns(user).cooldownEnd <= block.timestamp
 *   - User must have sufficient ETH on spoke chain for LayerZero fees
 *   - UnstakeMessenger must have hub peer configured
 *
 * Expected Outcome:
 *   - Cooldown cleared on hub (cooldownEnd = 0)
 *   - iTRY balance increased on spoke chain by underlyingAmount
 *
 * Usage:
 *   # On Spoke Chain (OP Sepolia):
 *   forge script script/test/composer/CrosschainUnstake_SpokeToHubToSpoke_RedeemerAddress.s.sol \
 *     --rpc-url $OP_SEPOLIA_RPC_URL \
 *     --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - UNSTAKE_MESSENGER: UnstakeMessenger address on spoke chain (OP Sepolia)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - SEPOLIA_RPC_URL: RPC URL for hub chain queries (Sepolia)
 *   - OP_SEPOLIA_RPC_URL: RPC URL for spoke chain (OP Sepolia)
 *   - HUB_STAKING: StakediTryCrosschain address on hub chain
 *   - SPOKE_ITRY_OFT: iTRY OFT address on spoke chain
 *
 * Alternatively, you can use REDEEMER_KEY directly:
 *   - REDEEMER_KEY: Redeemer's private key
 *
 * ===== FEE QUOTING =====
 *
 * The script now quotes both legs inline to keep LayerZero fees fresh:
 *   1. Quote wiTryVaultComposer.quoteUnstakeReturn() on Sepolia (hub) to get the base return-leg fee.
 *   2. Apply UnstakeMessenger.feeBufferBPS to that number locally to build the exact returnTripAllocation.
 *   3. Call UnstakeMessenger.quoteUnstakeWithReturnValue(returnTripAllocation) on OP Sepolia (spoke) to get
 *      the EXACT msg.value required for leg1 (no buffer - OApp requires exact fee).
 *   4. Immediately broadcast unstake{value: quotedFee}(returnTripAllocation).
 *
 * No UNSTAKE_FEE_OVERRIDE / RETURN_TRIP_ALLOCATION environment variables are needed.
 *
/**
 * @notice After successful execution:
 * 1. Note the LayerZero GUID displayed in the console output
 * 2. Visit the LayerZeroScan link provided to monitor message delivery
 * 3. Wait for 'Delivered' status (typically 1-3 minutes)
 * 4. Run the verification commands shown to confirm:
 *    - Cooldown cleared on hub chain (cooldownEnd = 0)
 *    - iTRY balance increased on spoke chain
 * 5. The balance increase should match the cooldown underlyingAmount
 */
contract CrosschainUnstake_SpokeToHubToSpoke_RedeemerAddress is Script {

    function run() public {
        require(block.chainid == 11155420, "Must run on OP Sepolia (Spoke Chain)");

        // ============ Load Environment Variables ============

        // Read redeemer key (direct or derived)
        uint256 redeemerKey;
        try vm.envUint("REDEEMER_KEY") returns (uint256 key) {
            redeemerKey = key;
            console2.log("Using REDEEMER_KEY from environment");
        } catch {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            KeyDerivation.ActorKeys memory keys = KeyDerivation.getActorKeys(vm, deployerKey);
            redeemerKey = keys.redeemer;
            console2.log("Derived redeemer key from DEPLOYER_PRIVATE_KEY");
        }

        address redeemerAddress = vm.addr(redeemerKey);
        address unstakeMessenger = vm.envAddress("UNSTAKE_MESSENGER");
        string memory hubRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        string memory spokeRpcUrl = vm.envString("OP_SEPOLIA_RPC_URL");
        address composerStakedUSDeV2 = vm.envAddress("HUB_STAKING");
        address iTryTokenSpoke = vm.envAddress("SPOKE_ITRY_OFT");

        console2.log("============================================");
        console2.log("CROSSCHAIN UNSTAKE - SPOKE -> HUB -> SPOKE");
        console2.log("============================================");
        console2.log("Flow: Complete unstaking after cooldown");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("UnstakeMessenger (Spoke):", unstakeMessenger);
        console2.log("StakediTryCrosschain (Hub):", composerStakedUSDeV2);
        console2.log("iTRY Token (Spoke):", iTryTokenSpoke);
        console2.log("============================================\n");

        // =======================================================================
        // CROSSCHAIN UNSTAKE FLOW - 5 PHASES
        // =======================================================================
        // Phase 1 (This Script - Spoke Chain): User initiates unstake via UnstakeMessenger
        // Phase 2 (Automatic - Hub Chain): wiTryVaultComposer._lzReceive() processes message
        // Phase 3 (Automatic - Hub Chain): wiTryVaultComposer calls vault.unstakeThroughComposer()
        // Phase 4 (Automatic - Hub Chain): Silo.withdrawCrosschain() sends iTRY back
        // Phase 5 (Automatic - Spoke Chain): iTryTokenOFT receives and transfers iTRY to user
        //
        // This script demonstrates Phase 1 and provides monitoring/verification for Phases 2-5
        // =======================================================================

        // ============ PHASE 1: Setup - Verify Cooldown on Hub ============

        console2.log("[PHASE 1] Setup - Verifying cooldown on hub chain...\n");

        // Create fork to query hub chain
        uint256 hubForkId = vm.createFork(hubRpcUrl);
        vm.selectFork(hubForkId);

        // Query cooldown state
        (uint104 cooldownEnd, uint256 underlyingAmount) =
            IStakediTryCrosschain(composerStakedUSDeV2).cooldowns(redeemerAddress);

        console2.log("Cooldown State (Hub Chain):");
        console2.log("  Cooldown End Timestamp:", cooldownEnd);
        console2.log("  Current Block Timestamp:", block.timestamp);
        console2.log("  Underlying Amount:", underlyingAmount / 1e18, "iTRY");

        // Validate cooldown exists
        require(cooldownEnd != 0, "ERROR: No active cooldown found for user");
        console2.log("  [OK] Active cooldown found");

        // Validate cooldown is complete
        require(block.timestamp >= cooldownEnd, "ERROR: Cooldown period not yet complete");
        console2.log("  [OK] Cooldown period complete");

        // Calculate time since cooldown completion
        uint256 timeSinceComplete = block.timestamp - cooldownEnd;
        uint256 daysSinceComplete = timeSinceComplete / 86400;
        uint256 hoursSinceComplete = (timeSinceComplete % 86400) / 3600;
        console2.log("  Days since cooldown complete:", daysSinceComplete);
        console2.log("  Hours since cooldown complete:", hoursSinceComplete);
        console2.log("");

        // Switch back to spoke chain
        uint256 spokeForkId = vm.createFork(spokeRpcUrl);
        vm.selectFork(spokeForkId);

        // ============ PHASE 2: Record Initial State on Spoke ============

        console2.log("[PHASE 2] Recording initial state on spoke chain...\n");

        uint256 initialITryBalance = IERC20(iTryTokenSpoke).balanceOf(redeemerAddress);
        console2.log("Initial iTRY Balance (Spoke):", initialITryBalance / 1e18, "iTRY\n");

        // ============ PHASE 3: Quote Return Leg & Total Fee ============

        console2.log("[PHASE 3] Calculating total fee required...\n");

        uint256 totalRequired;
        uint256 returnTripAllocation;
        uint256 BPS_DENOMINATOR = 10000;
        uint32 hubEid = IUnstakeMessenger(unstakeMessenger).hubEid();
        uint256 bufferBPS = IUnstakeMessenger(unstakeMessenger).feeBufferBPS();

        console2.log("UnstakeMessenger Configuration:");
        console2.log("  Hub EID:", hubEid);
        console2.log("  Return Trip Buffer BPS:", bufferBPS);
        console2.log("");

        // Step 3a: Quote leg2 (hub→spoke) on hub chain
        console2.log("Switching to hub chain to quote return leg...");
        vm.selectFork(hubForkId);

        address vaultComposer = vm.envAddress("VAULT_COMPOSER");
        uint32 spokeEid = 40232;  // OP Sepolia destination

        (uint256 leg2Fee, uint256 leg2LzTokenFee) = IVaultComposer(vaultComposer).quoteUnstakeReturn(
            redeemerAddress,
            underlyingAmount,
            spokeEid
        );

        console2.log("Leg2 Fee (Hub -> Spoke):");
        console2.log("  Native Fee (wei):", leg2Fee);
        console2.log("  Native Fee (gwei):", string.concat(vm.toString(leg2Fee / 1e9), " gwei"));
        console2.log("  LZ Token Fee:", leg2LzTokenFee);

        require(leg2Fee > 0, "ERROR: Leg2 quote returned zero fee");

        // Apply buffer to the return trip allocation only
        returnTripAllocation = (leg2Fee * (BPS_DENOMINATOR + bufferBPS)) / BPS_DENOMINATOR;
        uint256 returnTripBuffer = returnTripAllocation - leg2Fee;

        console2.log("Return Trip Allocation:");
        console2.log("  Base (wei):", leg2Fee);
        console2.log("  Buffer (wei):", returnTripBuffer);
        console2.log("  Total Allocation (wei):", returnTripAllocation);
        console2.log("  Total Allocation (gwei):", string.concat(vm.toString(returnTripAllocation / 1e9), " gwei"));
        console2.log("");

        // Step 3b: Switch back to spoke chain and quote total fee inline
        vm.selectFork(spokeForkId);

        uint256 lzTokenFee;
        (totalRequired, lzTokenFee) =
            IUnstakeMessenger(unstakeMessenger).quoteUnstakeWithReturnValue(returnTripAllocation);

        require(totalRequired > 0, "ERROR: Unstake quote returned zero fee");

        console2.log("Quoted Total (Spoke -> Hub) - EXACT fee required:");
        console2.log("  Native Fee (wei):", totalRequired);
        console2.log("  Native Fee (gwei):", string.concat(vm.toString(totalRequired / 1e9), " gwei"));
        console2.log("  LZ Token Fee:", lzTokenFee);
        console2.log("");

        // Check ETH balance
        uint256 ethBalance = redeemerAddress.balance;
        console2.log("Redeemer ETH Balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= totalRequired, "ERROR: Insufficient ETH for total LayerZero fee");
        console2.log("  [OK] Sufficient ETH for total round-trip fee\n");

        // ============ PHASE 4: Execute Unstake ============

        console2.log("[PHASE 4] Executing unstake transaction...\n");

        vm.startBroadcast(redeemerKey);

        // Call unstake with total calculated fee and returnTripAllocation parameter
        console2.log("Calling UnstakeMessenger.unstake:");
        console2.log("  msg.value (wei):", totalRequired);
        console2.log("  msg.value (gwei):", string.concat(vm.toString(totalRequired / 1e9), " gwei"));
        console2.log("  returnTripAllocation (wei):", returnTripAllocation);
        console2.log("  returnTripAllocation (gwei):", string.concat(vm.toString(returnTripAllocation / 1e9), " gwei"));
        bytes32 guid = IUnstakeMessenger(unstakeMessenger).unstake{value: totalRequired}(returnTripAllocation);

        vm.stopBroadcast();

        console2.log("  [OK] Transaction sent!");
        console2.log("");
        console2.log("LayerZero Message GUID:");
        console2.log(vm.toString(guid));
        console2.log("");
        console2.log("============================================");
        console2.log("=== MONITORING ===");
        console2.log("============================================");
        console2.log("");
        console2.log("Track your message delivery at LayerZeroScan:");
        string memory scanUrl = string.concat(
            "https://testnet.layerzeroscan.com/tx/",
            vm.toString(guid)
        );
        console2.log(scanUrl);
        console2.log("");
        console2.log("TIMING:");
        console2.log("- Message delivery typically takes 1-3 minutes");
        console2.log("- Wait for 'Delivered' status before running verification commands");
        console2.log("- Check LayerZeroScan for real-time progress");
        console2.log("");

        // ============ PHASE 5: Monitoring Instructions ============

        console2.log("============================================");
        console2.log("=== TIMING GUIDANCE ===");
        console2.log("============================================");
        console2.log("");
        console2.log("WAIT 1-3 minutes for message delivery before verification.");
        console2.log("Check LayerZeroScan for 'Delivered' status first.");
        console2.log("");

        console2.log("============================================");
        console2.log("[PHASE 5] MONITORING & VERIFICATION");
        console2.log("============================================\n");

        console2.log("1. TRACK MESSAGE DELIVERY:");
        console2.log("   Visit LayerZeroScan to track your transaction:");
        console2.log("   https://testnet.layerzeroscan.com/");
        console2.log("   Search for GUID:", vm.toString(guid));
        console2.log("");

        console2.log("2. EXPECTED MESSAGE FLOW:");
        console2.log("   Step 1: Spoke -> Hub (UnstakeMessenger -> wiTryVaultComposer)");
        console2.log("           wiTryVaultComposer._lzReceive() processes unstake request");
        console2.log("           StakediTryCrosschain.unstakeThroughComposer() executes");
        console2.log("   Step 2: Hub -> Spoke (iTrySilo -> iTryTokenOFT)");
        console2.log("           iTRY tokens minted to redeemer on spoke chain");
        console2.log("");

        console2.log("3. VERIFY COOLDOWN CLEARED ON HUB:");
        console2.log("   After LayerZeroScan shows delivery, check cooldown state:");
        console2.log("   ");
        console2.log("   cast call", composerStakedUSDeV2, "\\");
        console2.log("     \"cooldowns(address)((uint104,uint256))\" \\");
        console2.log("    ", redeemerAddress, "\\");
        console2.log("     --rpc-url $SEPOLIA_RPC_URL");
        console2.log("");
        console2.log("   Expected: cooldownEnd = 0, underlyingAmount = 0");
        console2.log("");

        console2.log("4. VERIFY iTRY BALANCE INCREASE ON SPOKE:");
        console2.log("   Check final iTRY balance:");
        console2.log("   ");
        console2.log("   cast call", iTryTokenSpoke, "\\");
        console2.log("     \"balanceOf(address)\" \\");
        console2.log("    ", redeemerAddress, "\\");
        console2.log("     --rpc-url $OP_SEPOLIA_RPC_URL");
        console2.log("");
        console2.log("   Expected increase:", underlyingAmount / 1e18, "iTRY");
        console2.log("   Initial balance:", initialITryBalance / 1e18, "iTRY");
        console2.log("   Expected final:", (initialITryBalance + underlyingAmount) / 1e18, "iTRY");
        console2.log("");

        console2.log("============================================");
        console2.log("[SUCCESS] Unstake transaction submitted!");
        console2.log("Wait for LayerZero message delivery (~5-10 minutes)");
        console2.log("============================================");
    }
}
