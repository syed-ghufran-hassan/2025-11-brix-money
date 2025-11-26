// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Protocol contracts
import {iTry} from "../src/token/iTRY/iTry.sol";
import {DLFToken} from "../src/external/DLFToken.sol";
import {RedstoneNAVFeed} from "../src/protocol/RedstoneNAVFeed.sol";
import {iTryIssuer} from "../src/protocol/iTryIssuer.sol";
import {IFastAccessVault} from "../src/protocol/interfaces/IFastAccessVault.sol";
import {YieldForwarder} from "../src/protocol/YieldForwarder.sol";
import {StakediTry} from "../src/token/wiTRY/StakediTry.sol";

/**
 * @title Integration Test: Hub Chain Complete Flow
 * @notice Tests the full iTRY protocol flow on hub chain
 * @dev Tests: Mint → Stake → Yield → Distribute
 *
 * Test Flow:
 * 1. Deploy all real contracts (no mocks)
 * 2. Mint iTRY using DLF collateral
 * 3. Stake iTRY to get wiTRY shares
 * 4. Simulate NAV appreciation (yield generation)
 * 5. Process and distribute yield
 * 6. Test redemptions
 * 7. Verify all balances and state
 */
contract IntegrationHubChainTest is Test {
    // ============================================
    // State Variables
    // ============================================

    // Core contracts
    iTry public itryToken;
    iTry public itryImplementation;
    ERC1967Proxy public itryProxy;
    DLFToken public dlfToken;
    RedstoneNAVFeed public oracle;

    // Protocol contracts
    iTryIssuer public issuer;
    IFastAccessVault public vault;
    YieldForwarder public yieldForwarder;
    StakediTry public staking;

    // Test actors
    address public admin;
    address public treasury;
    address public custodian;
    address public user1;
    address public user2;
    address public user3;

    // Constants
    uint256 constant INITIAL_NAV_PRICE = 1e18; // 1:1
    uint256 constant BUFFER_TARGET_BPS = 500; // 5%
    uint256 constant MINIMUM_BUFFER_BALANCE = 0;
    uint256 constant BASIS_POINTS = 10_000;

    bytes32 constant REWARDER_ROLE = keccak256("REWARDER_ROLE");
    bytes32 constant MINTER_CONTRACT = keccak256("MINTER_CONTRACT");

    // ============================================
    // Setup
    // ============================================

    function setUp() public {
        // Setup test actors
        admin = address(this);
        treasury = makeAddr("treasury");
        custodian = makeAddr("custodian");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy core contracts
        _deployCore();

        // Deploy protocol contracts
        _deployProtocol();

        // Wire contracts together
        _wireContracts();

        // Setup initial state
        _setupInitialState();
    }

    function _deployCore() internal {
        // Deploy oracle (mock oracle for testing)
        oracle = new RedstoneNAVFeed();
        vm.mockCall(
            address(oracle), abi.encodeWithSelector(RedstoneNAVFeed.price.selector), abi.encode(INITIAL_NAV_PRICE)
        );

        // Deploy DLF token
        dlfToken = new DLFToken(admin);

        // Deploy iTry implementation
        itryImplementation = new iTry();

        // Deploy iTry proxy
        bytes memory initData = abi.encodeWithSelector(
            iTry.initialize.selector,
            admin, // admin
            admin // initial minter (will be replaced)
        );

        itryProxy = new ERC1967Proxy(address(itryImplementation), initData);
        itryToken = iTry(address(itryProxy));
    }

    function _deployProtocol() internal {
        // Deploy StakediTry (wiTRY)
        staking = new StakediTry(IERC20(address(itryToken)), admin, admin);

        // Deploy YieldForwarder
        yieldForwarder = new YieldForwarder(address(itryToken), treasury);

        // Deploy iTryIssuer (now creates FastAccessVault internally - needs 11 parameters)
        issuer = new iTryIssuer(
            address(itryToken),
            address(dlfToken),
            address(oracle),
            treasury,
            address(yieldForwarder),
            custodian,
            admin, // _initialAdmin
            0, // _initialIssued
            0, // _initialDLFUnderCustody
            BUFFER_TARGET_BPS, // _vaultTargetPercentageBPS
            MINIMUM_BUFFER_BALANCE // _vaultMinimumBalance
        );

        // Get the vault that was deployed internally by iTryIssuer
        vault = issuer.liquidityVault();
    }

    function _wireContracts() internal {
        // Note: Vault issuer is already set correctly since iTryIssuer deployed it

        // Grant MINTER_CONTRACT role to issuer
        itryToken.grantRole(MINTER_CONTRACT, address(issuer));

        // Grant REWARDER_ROLE to issuer on staking contract
        staking.grantRole(REWARDER_ROLE, address(issuer));

        // Whitelist users on issuer
        issuer.addToWhitelist(user1);
        issuer.addToWhitelist(user2);
        issuer.addToWhitelist(user3);
    }

    function _setupInitialState() internal {
        // Mint DLF to users for testing
        dlfToken.mint(user1, 10_000e18);
        dlfToken.mint(user2, 10_000e18);
        dlfToken.mint(user3, 10_000e18);

        // Grant REWARDER_ROLE to admin for manual staker yield distribution
        // In v2, YieldForwarder only forwards to treasury; staker rewards are manually distributed
        bytes32 rewarderRole = keccak256("REWARDER_ROLE");
        vm.prank(admin);
        staking.grantRole(rewarderRole, admin);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _setNAVPrice(uint256 newPrice) internal {
        vm.mockCall(address(oracle), abi.encodeWithSelector(RedstoneNAVFeed.price.selector), abi.encode(newPrice));
    }

    function _mintITry(address user, uint256 dlfAmount) internal returns (uint256 itryMinted) {
        vm.startPrank(user);
        dlfToken.approve(address(issuer), dlfAmount);
        itryMinted = issuer.mintITRY(dlfAmount, 0);
        vm.stopPrank();
    }

    function _stakeITry(address user, uint256 itryAmount) internal returns (uint256 sharesMinted) {
        vm.startPrank(user);
        itryToken.approve(address(staking), itryAmount);
        sharesMinted = staking.deposit(itryAmount, user);
        vm.stopPrank();
    }

    // ============================================
    // Test: Complete Integration Flow
    // ============================================

    /// @notice Test the complete flow from minting to yield distribution
    function test_integration_completeFlow() public {
        console.log("\n=== INTEGRATION TEST: Complete Hub Chain Flow ===\n");

        // Phase 1-3: Setup users and stake
        (
            uint256 user1StakeAmount,
            uint256 user1SharesMinted,
            uint256 user2ItryMinted,
            uint256 user2SharesMinted,
            uint256 user3ItryMinted
        ) = _setupUsersAndStake();

        // Phase 4-5: Generate and process yield
        uint256 yieldMinted = _generateAndProcessYield();

        // Phase 6: Distribute yield
        _distributeYield(yieldMinted);

        // Phase 7: Verify staker shares
        _verifyStakerShares(user1StakeAmount, user1SharesMinted, user2ItryMinted, user2SharesMinted);

        // Phase 8: Test redemption
        _testRedemption(user3ItryMinted);

        // Final state
        _logFinalState();
    }

    function _setupUsersAndStake() internal returns (uint256, uint256, uint256, uint256, uint256) {
        // Phase 1: Minting iTRY
        console.log("PHASE 1: Minting iTRY with DLF");
        uint256 user1DlfAmount = 1000e18;
        uint256 user1InitialDlf = dlfToken.balanceOf(user1);
        uint256 user1ItryMinted = _mintITry(user1, user1DlfAmount);

        console.log("  User1 deposited DLF:", user1DlfAmount / 1e18);
        console.log("  User1 received iTRY:", user1ItryMinted / 1e18);

        assertEq(itryToken.balanceOf(user1), user1ItryMinted, "User1 should receive iTRY");
        assertEq(dlfToken.balanceOf(user1), user1InitialDlf - user1DlfAmount, "User1 DLF should be spent");
        assertGt(issuer.getCollateralUnderCustody(), 0, "Custody should hold DLF");

        // Phase 2: Staking iTRY
        console.log("\nPHASE 2: Staking iTRY for wiTRY shares");
        uint256 user1StakeAmount = user1ItryMinted / 2;
        uint256 user1SharesMinted = _stakeITry(user1, user1StakeAmount);

        console.log("  User1 staked iTRY:", user1StakeAmount / 1e18);
        console.log("  User1 received wiTRY shares:", user1SharesMinted / 1e18);

        assertEq(staking.balanceOf(user1), user1SharesMinted, "User1 should receive wiTRY shares");
        assertEq(itryToken.balanceOf(user1), user1ItryMinted - user1StakeAmount, "User1 iTRY should decrease");
        assertEq(staking.totalAssets(), user1StakeAmount, "Staking contract should hold iTRY");

        // Phase 3: Additional Users
        console.log("\nPHASE 3: Additional users mint and stake");
        uint256 user2ItryMinted = _mintITry(user2, 500e18);
        uint256 user2SharesMinted = _stakeITry(user2, user2ItryMinted);
        uint256 user3ItryMinted = _mintITry(user3, 300e18);

        console.log("  User2 minted iTRY:", user2ItryMinted / 1e18);
        console.log("  User2 staked all for wiTRY:", user2SharesMinted / 1e18);
        console.log("  User3 minted iTRY (not staked):", user3ItryMinted / 1e18);

        console.log("\n  Total iTRY supply:", itryToken.totalSupply() / 1e18);
        console.log("  Total staked:", staking.totalAssets() / 1e18);

        return (user1StakeAmount, user1SharesMinted, user2ItryMinted, user2SharesMinted, user3ItryMinted);
    }

    function _generateAndProcessYield() internal returns (uint256) {
        console.log("\nPHASE 4: NAV price increases (yield generation)");
        uint256 newNAVPrice = 1.1e18;
        _setNAVPrice(newNAVPrice);
        console.log("  NAV price increased from 1.0 to 1.1 (10% yield)");

        {
            uint256 totalCustody = issuer.getCollateralUnderCustody();
            uint256 collateralValue = (totalCustody * newNAVPrice) / 1e18;
            uint256 expectedYield = collateralValue - itryToken.totalSupply();
            console.log("  Expected yield:", expectedYield / 1e18, "iTRY");
        }

        console.log("\nPHASE 5: Processing accumulated yield");
        uint256 yieldMinted = issuer.processAccumulatedYield();
        console.log("  Yield minted:", yieldMinted / 1e18, "iTRY");
        assertGt(yieldMinted, 0, "Should mint positive yield");

        return yieldMinted;
    }

    function _distributeYield(uint256 yieldMinted) internal {
        console.log("\nPHASE 6: Distributing yield");
        uint256 stakingBalanceBefore = staking.totalAssets();
        uint256 stakerPortion = yieldMinted / 2;

        vm.startPrank(treasury);
        itryToken.transfer(admin, stakerPortion);
        vm.stopPrank();

        vm.startPrank(admin);
        itryToken.approve(address(staking), stakerPortion);
        staking.transferInRewards(stakerPortion);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 hours);

        uint256 stakersYield = staking.totalAssets() - stakingBalanceBefore;
        console.log("  Treasury received:", (yieldMinted - stakerPortion) / 1e18, "iTRY");
        console.log("  Stakers received:", stakersYield / 1e18, "iTRY");
    }

    function _verifyStakerShares(
        uint256 user1StakeAmount,
        uint256 user1SharesMinted,
        uint256 user2ItryMinted,
        uint256 user2SharesMinted
    ) internal {
        console.log("\nPHASE 7: Verify staker share values");
        uint256 user1ShareValue = staking.convertToAssets(user1SharesMinted);
        uint256 user2ShareValue = staking.convertToAssets(user2SharesMinted);

        console.log("  User1 shares:", user1SharesMinted / 1e18);
        console.log("  User1 share value:", user1ShareValue / 1e18, "iTRY");
        console.log("  User2 shares:", user2SharesMinted / 1e18);
        console.log("  User2 share value:", user2ShareValue / 1e18, "iTRY");

        assertGt(user1ShareValue, user1StakeAmount, "User1 shares should appreciate");
        assertGt(user2ShareValue, user2ItryMinted, "User2 shares should appreciate");
    }

    function _testRedemption(uint256 user3ItryMinted) internal {
        console.log("\nPHASE 8: Test redemption");
        uint256 redeemAmount = user3ItryMinted / 2;
        uint256 user3DlfBefore = dlfToken.balanceOf(user3);

        vm.startPrank(user3);
        itryToken.approve(address(issuer), redeemAmount);
        bool fromBuffer = issuer.redeemITRY(redeemAmount, 0);
        vm.stopPrank();

        uint256 dlfRedeemed = dlfToken.balanceOf(user3) - user3DlfBefore;
        console.log("  User3 redeemed iTRY:", redeemAmount / 1e18);
        console.log("  User3 received DLF:", dlfRedeemed / 1e18);
        console.log("  From buffer:", fromBuffer);

        assertGt(dlfRedeemed, 0, "User3 should receive DLF");
        assertEq(itryToken.balanceOf(user3), user3ItryMinted - redeemAmount, "User3 iTRY should decrease");
    }

    function _logFinalState() internal {
        console.log("\n=== INTEGRATION TEST COMPLETE ===\n");
        console.log("FINAL STATE:");
        console.log("  Total iTRY supply:", itryToken.totalSupply() / 1e18);
        console.log("  Total in staking:", staking.totalAssets() / 1e18);
        console.log("  Total custody:", issuer.getCollateralUnderCustody() / 1e18, "DLF");
        console.log("  Buffer balance:", dlfToken.balanceOf(address(vault)) / 1e18, "DLF");
    }

    // ============================================
    // Test: Redemption Scenarios
    // ============================================

    /// @notice Test redemption from buffer vs custodian
    function test_integration_redemptionScenarios() public {
        // Setup: Mint iTRY and fill buffer
        uint256 mintAmount = 1000e18;
        _mintITry(user1, mintAmount);

        // Test 1: Redeem from buffer (small amount)
        uint256 smallRedeem = 10e18;
        vm.startPrank(user1);
        itryToken.approve(address(issuer), smallRedeem);
        bool fromBuffer = issuer.redeemITRY(smallRedeem, 0);
        vm.stopPrank();

        assertTrue(fromBuffer, "Small redemption should be from buffer");

        // Test 2: Redeem large amount (exceeds buffer)
        uint256 largeRedeem = 900e18;
        uint256 bufferBalance = vault.getAvailableBalance();

        vm.startPrank(user1);
        itryToken.approve(address(issuer), largeRedeem);
        fromBuffer = issuer.redeemITRY(largeRedeem, 0);
        vm.stopPrank();

        if (largeRedeem > bufferBalance) {
            assertFalse(fromBuffer, "Large redemption should be from custodian");
        }
    }

    // ============================================
    // Test: Multiple Yield Distributions
    // ============================================

    /// @notice Test multiple rounds of yield distribution
    function test_integration_multipleYieldRounds() public {
        // Setup: Users mint and stake
        uint256 user1Minted = _mintITry(user1, 1000e18);
        uint256 user1Staked = _stakeITry(user1, user1Minted);

        // Round 1: 5% yield
        uint256 shareValue1 = _processYieldRound(1.05e18, user1Staked, 1);

        // Round 2: Another 5% on top
        uint256 shareValue2 = _processYieldRound(1.1025e18, user1Staked, 2);

        // Assertions
        assertGt(shareValue2, shareValue1, "Share value should keep growing");
    }

    function _processYieldRound(uint256 navPrice, uint256 userStaked, uint256 roundNumber) internal returns (uint256) {
        _setNAVPrice(navPrice);
        uint256 yieldAmount = issuer.processAccumulatedYield();

        // Distribute staker portion (50% of yield)
        uint256 stakerPortion = yieldAmount / 2;
        vm.startPrank(treasury);
        itryToken.transfer(admin, stakerPortion);
        vm.stopPrank();

        vm.startPrank(admin);
        itryToken.approve(address(staking), stakerPortion);
        staking.transferInRewards(stakerPortion);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 hours);

        uint256 shareValue = staking.convertToAssets(userStaked);
        console.log("Round %d: Yield = %d, Share value = %d", roundNumber, yieldAmount / 1e18, shareValue / 1e18);
        assertGt(yieldAmount, 0, "Should generate positive yield");

        return shareValue;
    }
}
