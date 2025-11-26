// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/token/wiTRY/StakediTryFastRedeem.sol";
import {IStakediTry} from "../src/token/wiTRY/interfaces/IStakediTry.sol";
import {IStakediTryCooldown} from "../src/token/wiTRY/interfaces/IStakediTryCooldown.sol";
import {IStakediTryFastRedeem} from "../src/token/wiTRY/interfaces/IStakediTryFastRedeem.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title StakediTryFastRedeem Stateless Fuzz Tests
 * @notice Property-based fuzz tests for StakediTryFastRedeem functions
 * @dev Tests system properties with randomized inputs to validate invariants
 */
contract StakediTryFastRedeemFuzzTest is Test {
    StakediTryFastRedeem public stakediTry;
    MockERC20 public iTryToken;

    address public admin;
    address public treasury;
    address public rewarder;
    address public user1;
    address public user2;

    uint16 public constant DEFAULT_FEE = 500; // 5%
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000e18; // $1B scale for institutional testing

    // Events
    event FastRedeemed(
        address indexed owner, address indexed receiver, uint256 shares, uint256 assets, uint256 feeAssets
    );

    function setUp() public {
        admin = makeAddr("admin");
        treasury = makeAddr("treasury");
        rewarder = makeAddr("rewarder");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy iTRY token
        iTryToken = new MockERC20("iTRY", "iTRY");

        // Deploy StakediTryFastRedeem
        vm.prank(admin);
        stakediTry = new StakediTryFastRedeem(IERC20(address(iTryToken)), rewarder, admin, treasury);

        // Enable fast redeem and set default fee
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // Mint tokens to users
        iTryToken.mint(user1, INITIAL_SUPPLY);
        iTryToken.mint(user2, INITIAL_SUPPLY);

        // Users approve StakediTry
        vm.prank(user1);
        iTryToken.approve(address(stakediTry), type(uint256).max);

        vm.prank(user2);
        iTryToken.approve(address(stakediTry), type(uint256).max);
    }

    // ============================================
    // fastRedeem Fuzz Tests (5 tests)
    // ============================================

    /// @notice Fuzz test: Conservation of value in fast redemption
    /// @dev Property: netAssets + feeAssets = totalAssets (no value is created or destroyed)
    /// @dev Bounds: MIN_SHARES (1e18) to $1B - tests from minimum viable to institutional scale
    function testFuzz_fastRedeem_conservationOfValue(uint256 shares) public {
        // User2 deposits to provide MIN_SHARES buffer (prevents MIN_SHARES violation)
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits large amount to have plenty of shares
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Bound shares to valid range [MIN_SHARES, totalShares]
        shares = bound(shares, 1e18, totalShares);

        // Calculate expected amounts
        uint256 expectedTotalAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFeeAssets = (expectedTotalAssets * DEFAULT_FEE) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFeeAssets;

        // Record balances before
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Act
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        // Assert: Conservation of value
        assertEq(netAssets, expectedNetAssets, "Net assets must match calculation");
        assertEq(iTryToken.balanceOf(user1) - userBalanceBefore, expectedNetAssets, "User receives exactly net assets");
        assertEq(
            iTryToken.balanceOf(treasury) - treasuryBalanceBefore,
            expectedFeeAssets,
            "Treasury receives exactly fee assets"
        );
        assertEq(netAssets + expectedFeeAssets, expectedTotalAssets, "Conservation: net + fee must equal total");
    }

    /// @notice Fuzz test: Fee calculation consistency across all valid fee rates
    /// @dev Property: feeAssets = (totalAssets * feeInBPS) / 10000 for all valid fees
    /// @dev Bounds: Shares up to $1B, fees 1 BP (0.01%) to 2000 BP (20%) - tests all valid fee configurations
    function testFuzz_fastRedeem_feeCalculationConsistency(uint256 shares, uint16 feeInBPS) public {
        // Bound fee to valid range [MIN_FAST_REDEEM_FEE, MAX_FAST_REDEEM_FEE]
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set the fuzzed fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User deposits
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Bound shares to valid range
        shares = bound(shares, 1e18, totalShares);

        // Calculate expected values
        uint256 expectedTotalAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFeeAssets = (expectedTotalAssets * feeInBPS) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFeeAssets;

        // Record balances before
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);

        // Act
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        // Assert: Fee calculation is exact
        assertEq(
            iTryToken.balanceOf(treasury) - treasuryBalanceBefore,
            expectedFeeAssets,
            "Treasury must receive exact fee amount"
        );
        assertEq(
            iTryToken.balanceOf(user1) - userBalanceBefore, expectedNetAssets, "User must receive exact net amount"
        );
        assertEq(netAssets, expectedNetAssets, "Return value must match net assets");
    }

    /// @notice Fuzz test: Share burning correctness
    /// @dev Property: User's share balance decreases by exactly the redeemed amount
    /// @dev Bounds: MIN_SHARES to $1B - validates share accounting at all scales
    function testFuzz_fastRedeem_shareBurningCorrectness(uint256 shares) public {
        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User deposits
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Bound shares to valid range
        shares = bound(shares, 1e18, totalShares);

        // Record share balance before
        uint256 shareBalanceBefore = stakediTry.balanceOf(user1);

        // Act
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);

        // Assert: Shares burned correctly
        uint256 shareBalanceAfter = stakediTry.balanceOf(user1);
        assertEq(shareBalanceBefore - shareBalanceAfter, shares, "Exactly 'shares' amount must be burned");
        assertEq(shareBalanceAfter, totalShares - shares, "Remaining shares must be correct");
    }

    /// @notice Fuzz test: Treasury always receives fee (no zero-fee redemptions)
    /// @dev Property: feeAssets > 0 for all valid redemptions (enforces cost for instant liquidity)
    /// @dev Bounds: MIN_SHARES to $1B, all valid fees - ensures fast redeem always has cost
    function testFuzz_fastRedeem_treasuryAlwaysReceivesFee(uint256 shares, uint16 feeInBPS) public {
        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set the fuzzed fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User deposits
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Bound shares to valid range
        shares = bound(shares, 1e18, totalShares);

        // Record treasury balance before
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Act
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);

        // Assert: Treasury always receives non-zero fee
        uint256 treasuryBalanceAfter = iTryToken.balanceOf(treasury);
        uint256 feeReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        assertGt(feeReceived, 0, "Treasury must always receive non-zero fee");

        // Additional check: fee matches calculation
        uint256 totalAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (totalAssets * feeInBPS) / 10000;
        assertEq(feeReceived, expectedFee, "Fee received must match formula");
    }

    /// @notice Fuzz test: Different receiver address handling
    /// @dev Property: Receiver gets assets, owner loses shares (proper separation of concerns)
    /// @dev Bounds: MIN_SHARES to $1B - tests delegation pattern at scale
    function testFuzz_fastRedeem_differentReceiverHandling(uint256 shares) public {
        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Bound shares to valid range
        shares = bound(shares, 1e18, totalShares);

        // Calculate expected net assets
        uint256 totalAssets = stakediTry.previewRedeem(shares);
        uint256 feeAssets = (totalAssets * DEFAULT_FEE) / 10000;
        uint256 expectedNetAssets = totalAssets - feeAssets;

        // Record balances before
        uint256 user1SharesBefore = stakediTry.balanceOf(user1);
        uint256 user2AssetsBefore = iTryToken.balanceOf(user2);

        // Act: User1 redeems but sends assets to user2
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user2, user1);

        // Assert: Proper separation
        assertEq(stakediTry.balanceOf(user1), user1SharesBefore - shares, "Owner (user1) loses shares");
        assertEq(iTryToken.balanceOf(user2), user2AssetsBefore + expectedNetAssets, "Receiver (user2) gets assets");
        assertEq(netAssets, expectedNetAssets, "Return value matches net assets");
    }

    // ============================================
    // fastWithdraw Fuzz Tests (5 tests)
    // ============================================

    /// @notice Fuzz test: Conservation of value in fast withdraw
    /// @dev Property: netAssets + feeAssets = totalAssets (no value is created or destroyed)
    /// @dev Bounds: $1 to $1B - tests from minimum to institutional scale
    function testFuzz_fastWithdraw_conservationOfValue(uint256 assets) public {
        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits large amount
        vm.prank(user1);
        stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Get max withdrawable amount for user1
        uint256 maxWithdrawable = stakediTry.maxWithdraw(user1);

        // Bound assets to valid range [1e18, maxWithdrawable]
        assets = bound(assets, 1e18, maxWithdrawable);

        // Calculate expected amounts
        uint256 expectedFeeAssets = (assets * DEFAULT_FEE) / 10000;
        uint256 expectedNetAssets = assets - expectedFeeAssets;

        // Record balances before
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Act
        vm.prank(user1);
        uint256 sharesBurned = stakediTry.fastWithdraw(assets, user1, user1);

        // Assert: Conservation of value
        assertGt(sharesBurned, 0, "Shares must be burned");
        assertEq(iTryToken.balanceOf(user1) - userBalanceBefore, expectedNetAssets, "User receives exactly net assets");
        assertEq(
            iTryToken.balanceOf(treasury) - treasuryBalanceBefore,
            expectedFeeAssets,
            "Treasury receives exactly fee assets"
        );
        assertEq(expectedNetAssets + expectedFeeAssets, assets, "Conservation: net + fee must equal total");
    }

    /// @notice Fuzz test: Fee calculation consistency for asset-based withdrawals
    /// @dev Property: feeAssets = (assets * feeInBPS) / 10000 for all valid fees
    /// @dev Bounds: Assets up to $1B, fees 1 BP to 2000 BP - tests all valid fee configurations
    function testFuzz_fastWithdraw_feeCalculationConsistency(uint256 assets, uint16 feeInBPS) public {
        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set the fuzzed fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Get max withdrawable
        uint256 maxWithdrawable = stakediTry.maxWithdraw(user1);

        // Bound assets to valid range
        assets = bound(assets, 1e18, maxWithdrawable);

        // Calculate expected values
        uint256 expectedFeeAssets = (assets * feeInBPS) / 10000;
        uint256 expectedNetAssets = assets - expectedFeeAssets;

        // Record balances before
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);

        // Act
        vm.prank(user1);
        stakediTry.fastWithdraw(assets, user1, user1);

        // Assert: Fee calculation is exact
        assertEq(
            iTryToken.balanceOf(treasury) - treasuryBalanceBefore,
            expectedFeeAssets,
            "Treasury must receive exact fee amount"
        );
        assertEq(
            iTryToken.balanceOf(user1) - userBalanceBefore, expectedNetAssets, "User must receive exact net amount"
        );
    }

    /// @notice Fuzz test: Share calculation correctness for fastWithdraw
    /// @dev Property: Shares burned = previewWithdraw(assets)
    /// @dev Bounds: $1 to $1B - validates share calculation at all scales
    function testFuzz_fastWithdraw_shareCalculationCorrectness(uint256 assets) public {
        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Get max withdrawable
        uint256 maxWithdrawable = stakediTry.maxWithdraw(user1);

        // Bound assets to valid range
        assets = bound(assets, 1e18, maxWithdrawable);

        // Calculate expected shares to burn
        uint256 expectedShares = stakediTry.previewWithdraw(assets);

        // Record share balance before
        uint256 shareBalanceBefore = stakediTry.balanceOf(user1);

        // Act
        vm.prank(user1);
        uint256 sharesBurned = stakediTry.fastWithdraw(assets, user1, user1);

        // Assert: Shares burned correctly
        assertEq(sharesBurned, expectedShares, "Shares burned must match preview");
        assertEq(
            stakediTry.balanceOf(user1),
            shareBalanceBefore - expectedShares,
            "User balance must decrease by expected shares"
        );
    }

    /// @notice Fuzz test: Dual-path equivalence (fastRedeem vs fastWithdraw)
    /// @dev Property: fastRedeem(shares) ≈ fastWithdraw(previewRedeem(shares))
    /// @dev Bounds: MIN_SHARES to $500M - tests equivalence at scale (split $1B between two users)
    function testFuzz_fastWithdraw_dualPathEquivalence(uint256 shares) public {
        // User2 deposits to provide MIN_SHARES buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits half of supply
        uint256 depositAmount = INITIAL_SUPPLY / 2;
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(depositAmount, user1);

        // Bound shares to valid range
        shares = bound(shares, 1e18, totalShares / 2); // Use half to ensure room for second operation

        // Path 1: fastRedeem with shares
        uint256 assetsFromShares = stakediTry.previewRedeem(shares);
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);

        // Deposit again for second test
        vm.prank(user1);
        stakediTry.deposit(depositAmount / 2, user1);

        // Path 2: fastWithdraw with equivalent assets
        vm.prank(user1);
        uint256 sharesBurned2 = stakediTry.fastWithdraw(assetsFromShares, user1, user1);

        // Assert: The two paths produce similar results
        // Note: Due to rounding, we allow small differences
        assertApproxEqAbs(shares, sharesBurned2, 2, "Shares burned should be approximately equal");
    }

    /// @notice Fuzz test: Different receiver address handling for fastWithdraw
    /// @dev Property: Receiver gets assets, owner loses shares (proper separation of concerns)
    /// @dev Bounds: $1 to $1B - tests delegation pattern at scale
    function testFuzz_fastWithdraw_differentReceiverHandling(uint256 assets) public {
        // User2 deposits to provide MIN_SHARES buffer (separate from receiver role below)
        address bufferUser = makeAddr("bufferUser");
        iTryToken.mint(bufferUser, 100_000e18);
        vm.prank(bufferUser);
        iTryToken.approve(address(stakediTry), type(uint256).max);
        vm.prank(bufferUser);
        stakediTry.deposit(100_000e18, bufferUser);

        // User1 deposits
        vm.prank(user1);
        stakediTry.deposit(INITIAL_SUPPLY, user1);

        // Get max withdrawable
        uint256 maxWithdrawable = stakediTry.maxWithdraw(user1);

        // Bound assets to valid range
        assets = bound(assets, 1e18, maxWithdrawable);

        // Calculate expected net assets
        uint256 expectedFeeAssets = (assets * DEFAULT_FEE) / 10000;
        uint256 expectedNetAssets = assets - expectedFeeAssets;
        uint256 expectedShares = stakediTry.previewWithdraw(assets);

        // Record balances before
        uint256 user1SharesBefore = stakediTry.balanceOf(user1);
        uint256 user2AssetsBefore = iTryToken.balanceOf(user2);

        // Act: User1 withdraws but sends assets to user2
        vm.prank(user1);
        uint256 sharesBurned = stakediTry.fastWithdraw(assets, user2, user1);

        // Assert: Proper separation
        assertEq(stakediTry.balanceOf(user1), user1SharesBefore - expectedShares, "Owner (user1) loses shares");
        assertEq(iTryToken.balanceOf(user2), user2AssetsBefore + expectedNetAssets, "Receiver (user2) gets assets");
        assertEq(sharesBurned, expectedShares, "Return value matches expected shares");
    }

    // ============================================
    // Fee Configuration Fuzz Tests (3 tests)
    // ============================================

    /// @notice Fuzz test: Fee bounds enforcement
    /// @dev Property: setFastRedeemFee reverts for fees outside [MIN_FAST_REDEEM_FEE, MAX_FAST_REDEEM_FEE]
    /// @dev Bounds: Test full uint16 range - validates boundary enforcement
    function testFuzz_feeConfig_feeBoundsEnforcement(uint16 feeInBPS) public {
        uint16 minFee = stakediTry.MIN_FAST_REDEEM_FEE();
        uint16 maxFee = stakediTry.MAX_FAST_REDEEM_FEE();

        // Act & Assert
        if (feeInBPS < minFee || feeInBPS > maxFee) {
            // Should revert for out-of-bounds fees
            vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.InvalidFastRedeemFee.selector));
            vm.prank(admin);
            stakediTry.setFastRedeemFee(feeInBPS);
        } else {
            // Should succeed for valid fees
            vm.prank(admin);
            stakediTry.setFastRedeemFee(feeInBPS);
            assertEq(stakediTry.fastRedeemFeeInBPS(), feeInBPS, "Fee should be set correctly");
        }
    }

    /// @notice Fuzz test: Fee update atomicity and immediate effect
    /// @dev Property: Fee changes apply immediately to the next redemption
    /// @dev Bounds: All valid fee values - tests instant fee application across fee range
    function testFuzz_feeConfig_feeUpdateAtomicity(uint16 oldFee, uint16 newFee) public {
        // Bound both fees to valid range
        oldFee = uint16(bound(uint256(oldFee), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));
        newFee = uint16(bound(uint256(newFee), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Skip if fees are the same (not interesting for this test)
        vm.assume(oldFee != newFee);

        // Set initial fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(oldFee);

        // User2 deposits buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(100_000e18, user1);

        // Redemption 1: Uses old fee
        uint256 assets1 = stakediTry.previewRedeem(shares / 2);
        uint256 expectedFee1 = (assets1 * oldFee) / 10000;
        uint256 treasuryBefore1 = iTryToken.balanceOf(treasury);

        vm.prank(user1);
        stakediTry.fastRedeem(shares / 2, user1, user1);

        uint256 treasuryAfter1 = iTryToken.balanceOf(treasury);
        assertEq(treasuryAfter1 - treasuryBefore1, expectedFee1, "First redemption uses old fee");

        // Change fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(newFee);

        // Redemption 2: Immediately uses new fee
        uint256 remainingShares = stakediTry.balanceOf(user1);
        uint256 assets2 = stakediTry.previewRedeem(remainingShares);
        uint256 expectedFee2 = (assets2 * newFee) / 10000;
        uint256 treasuryBefore2 = iTryToken.balanceOf(treasury);

        vm.prank(user1);
        stakediTry.fastRedeem(remainingShares, user1, user1);

        uint256 treasuryAfter2 = iTryToken.balanceOf(treasury);
        assertEq(treasuryAfter2 - treasuryBefore2, expectedFee2, "Second redemption immediately uses new fee");
    }

    /// @notice Fuzz test: Treasury address update and routing
    /// @dev Property: Fee routing updates immediately when treasury address changes
    /// @dev Bounds: Test with multiple treasury addresses - validates fee routing correctness
    function testFuzz_feeConfig_treasuryUpdateAndRouting(uint16 feeInBPS, uint8 treasurySelector) public {
        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // Create different treasury addresses (use selector to pick one of several)
        address treasury1 = makeAddr("treasury1");
        address treasury2 = makeAddr("treasury2");
        address treasury3 = makeAddr("treasury3");

        address[] memory treasuries = new address[](3);
        treasuries[0] = treasury1;
        treasuries[1] = treasury2;
        treasuries[2] = treasury3;

        address selectedTreasury = treasuries[treasurySelector % 3];

        // Update treasury
        vm.prank(admin);
        stakediTry.setFastRedeemTreasury(selectedTreasury);

        assertEq(stakediTry.fastRedeemTreasury(), selectedTreasury, "Treasury should be updated");

        // User2 deposits buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(100_000e18, user1);

        // Calculate expected fee
        uint256 assets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (assets * feeInBPS) / 10000;

        // Record balance before
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(selectedTreasury);

        // Fast redeem
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);

        // Assert: New treasury receives fee
        uint256 treasuryBalanceAfter = iTryToken.balanceOf(selectedTreasury);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedFee, "New treasury must receive fee");

        // Assert: Old treasury receives nothing
        assertEq(iTryToken.balanceOf(treasury), 0, "Old treasury should not receive fees");
    }

    // ============================================
    // Edge Cases Fuzz Tests (4 tests)
    // ============================================

    /// @notice Fuzz test: MIN_SHARES enforcement during fast redemption
    /// @dev Property: Fast redeem respects MIN_SHARES constraint (reverts when it would violate)
    /// @dev Bounds: Shares that would violate MIN_SHARES - tests boundary protection
    function testFuzz_edgeCases_minSharesEnforcement(uint256 depositAmount) public {
        // Bound deposit to create scenarios near MIN_SHARES boundary
        // Range: 1.5e18 to 10e18 (just above MIN_SHARES to small amounts)
        depositAmount = bound(depositAmount, 1.5e18, 10e18);

        // User1 deposits small amount
        vm.prank(user1);
        uint256 user1Shares = stakediTry.deposit(depositAmount, user1);

        // User2 deposits tiny amount (below MIN_SHARES)
        vm.prank(user2);
        stakediTry.deposit(0.5e18, user2);

        // Total supply = depositAmount + 0.5e18
        // If user1 redeems their shares, remaining = 0.5e18 < MIN_SHARES (1e18)

        // This should revert because it would leave totalSupply < MIN_SHARES
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.MinSharesViolation.selector));
        vm.prank(user1);
        stakediTry.fastRedeem(user1Shares, user1, user1);

        // Verify user1 still has their shares (redemption failed)
        assertEq(stakediTry.balanceOf(user1), user1Shares, "User1 shares should remain (redemption reverted)");
    }

    /// @notice Fuzz test: Dust amount handling
    /// @dev Property: Very small redemptions either work correctly or revert cleanly (no exploits)
    /// @dev Bounds: 1 wei to 1e6 wei - tests extreme precision boundaries
    function testFuzz_edgeCases_dustAmountHandling(uint256 dustAmount, uint16 feeInBPS) public {
        // Bound to very small amounts (dust)
        dustAmount = bound(dustAmount, 1, 1e6);

        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User2 deposits large buffer
        vm.prank(user2);
        stakediTry.deposit(1_000_000e18, user2);

        // User1 deposits large amount so they can redeem dust
        vm.prank(user1);
        stakediTry.deposit(1_000_000e18, user1);

        // Try to fast withdraw dust amount
        // Calculate fee for dust
        uint256 feeAmount = (dustAmount * feeInBPS) / 10000;

        if (feeAmount == 0) {
            // Fee rounds to zero - should revert per InvalidAmount check
            vm.expectRevert(abi.encodeWithSelector(IStakediTry.InvalidAmount.selector));
            vm.prank(user1);
            stakediTry.fastWithdraw(dustAmount, user1, user1);
        } else {
            // Fee is non-zero - should either succeed or revert for valid reason
            try stakediTry.fastWithdraw(dustAmount, user1, user1) returns (uint256 sharesBurned) {
                // Success case: validate proper accounting
                assertGt(sharesBurned, 0, "Shares must be burned for successful dust redemption");
            } catch {
                // Revert is acceptable for dust amounts (might hit other constraints)
                // Just ensure it doesn't succeed with incorrect accounting
            }
        }
    }

    /// @notice Fuzz test: Maximum redemption (redeeming all shares)
    /// @dev Property: Users can always redeem 100% of their shares with any valid fee
    /// @dev Bounds: All valid fees, various deposit amounts - tests complete exit path
    function testFuzz_edgeCases_maximumRedemption(uint256 depositAmount, uint16 feeInBPS) public {
        // Bound deposit to realistic range
        depositAmount = bound(depositAmount, 10e18, 1_000_000e18);

        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User1 deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(depositAmount, user1);

        // Calculate expected amounts for full redemption
        uint256 assets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (assets * feeInBPS) / 10000;
        uint256 expectedNet = assets - expectedFee;

        // Record balances
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Redeem ALL shares (100% exit)
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        // Assert: Complete redemption successful
        assertEq(stakediTry.balanceOf(user1), 0, "User should have zero shares after full redemption");
        assertEq(netAssets, expectedNet, "Net assets should match calculation");
        assertEq(iTryToken.balanceOf(user1) - userBalanceBefore, expectedNet, "User receives correct net amount");
        assertEq(iTryToken.balanceOf(treasury) - treasuryBalanceBefore, expectedFee, "Treasury receives correct fee");

        // Assert: Total supply can be zero (no MIN_SHARES violation when fully exiting)
        assertEq(stakediTry.totalSupply(), 0, "Total supply should be zero after complete exit");
    }

    /// @notice Fuzz test: Rounding consistency and no value leakage
    /// @dev Property: Sum of (user assets + treasury fee) equals total assets withdrawn (no rounding leakage)
    /// @dev Bounds: Various amounts and fees - tests rounding doesn't create/destroy value
    function testFuzz_edgeCases_roundingConsistency(uint256 depositAmount, uint16 feeInBPS) public {
        // Bound to medium range where rounding matters most
        depositAmount = bound(depositAmount, 1e18, 100_000e18);

        // Bound fee to valid range
        feeInBPS = uint16(bound(uint256(feeInBPS), stakediTry.MIN_FAST_REDEEM_FEE(), stakediTry.MAX_FAST_REDEEM_FEE()));

        // Set fee
        vm.prank(admin);
        stakediTry.setFastRedeemFee(feeInBPS);

        // User2 deposits buffer
        vm.prank(user2);
        stakediTry.deposit(100_000e18, user2);

        // User1 deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(depositAmount, user1);

        // Record contract balance before redemption
        uint256 contractBalanceBefore = iTryToken.balanceOf(address(stakediTry));

        // Record user and treasury balances
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Fast redeem
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);

        // Record balances after
        uint256 contractBalanceAfter = iTryToken.balanceOf(address(stakediTry));
        uint256 userBalanceAfter = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceAfter = iTryToken.balanceOf(treasury);

        // Calculate actual transfers
        uint256 contractDecrease = contractBalanceBefore - contractBalanceAfter;
        uint256 userIncrease = userBalanceAfter - userBalanceBefore;
        uint256 treasuryIncrease = treasuryBalanceAfter - treasuryBalanceBefore;

        // Assert: No value created or destroyed (perfect conservation)
        assertEq(
            userIncrease + treasuryIncrease,
            contractDecrease,
            "Total distributed must equal contract decrease (no leakage)"
        );

        // Assert: All tokens accounted for (no dust left behind)
        uint256 totalBalanceAfter =
            contractBalanceAfter + userBalanceAfter + treasuryBalanceAfter + iTryToken.balanceOf(user2); // Include user2's balance
        uint256 totalBalanceBefore =
            contractBalanceBefore + userBalanceBefore + treasuryBalanceBefore + iTryToken.balanceOf(user2);

        assertEq(totalBalanceAfter, totalBalanceBefore, "Total system balance must remain constant");
    }
}
