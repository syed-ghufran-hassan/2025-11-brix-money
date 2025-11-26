// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/token/wiTRY/StakediTryFastRedeem.sol";
import {IStakediTry} from "../src/token/wiTRY/interfaces/IStakediTry.sol";
import {IStakediTryCooldown} from "../src/token/wiTRY/interfaces/IStakediTryCooldown.sol";
import {IStakediTryFastRedeem} from "../src/token/wiTRY/interfaces/IStakediTryFastRedeem.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title StakediTryFastRedeem Tests
 * @notice Comprehensive tests for the fast redemption feature in StakediTryFastRedeem
 */
contract StakediTryV2FastRedeemTest is Test {
    StakediTryFastRedeem public stakediTry;
    MockERC20 public iTryToken;

    address public admin;
    address public treasury;
    address public rewarder;
    address public user1;
    address public user2;
    address public nonAdmin;

    uint16 public constant DEFAULT_FEE = 500; // 5%
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    // Events
    event FastRedeemed(
        address indexed owner, address indexed receiver, uint256 shares, uint256 assets, uint256 feeAssets
    );
    event FastRedeemEnabledUpdated(bool enabled);
    event FastRedeemFeeUpdated(uint16 previousFee, uint16 newFee);
    event FastRedeemTreasuryUpdated(address previousTreasury, address newTreasury);

    function setUp() public {
        admin = makeAddr("admin");
        treasury = makeAddr("treasury");
        rewarder = makeAddr("rewarder");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonAdmin = makeAddr("nonAdmin");

        // Deploy iTRY token
        iTryToken = new MockERC20("iTRY", "iTRY");

        // Deploy StakediTryFastRedeem
        vm.prank(admin);
        stakediTry = new StakediTryFastRedeem(IERC20(address(iTryToken)), rewarder, admin, treasury);

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
    // Constructor Tests (2 tests)
    // ============================================

    /// @notice Tests that constructor sets treasury correctly
    function test_constructor_setsTreasuryCorrectly() public {
        assertEq(stakediTry.fastRedeemTreasury(), treasury, "Treasury should be set");
    }

    /// @notice Tests that constructor reverts when treasury is zero
    function test_constructor_whenTreasuryIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.InvalidZeroAddress.selector));
        vm.prank(admin);
        new StakediTryFastRedeem(IERC20(address(iTryToken)), rewarder, admin, address(0));
    }

    // ============================================
    // setFastRedeemEnabled Tests (3 tests)
    // ============================================

    /// @notice Tests that non-admin cannot enable fast redeem
    function test_setFastRedeemEnabled_whenCallerNotAdmin_reverts() public {
        vm.expectRevert();
        vm.prank(nonAdmin);
        stakediTry.setFastRedeemEnabled(true);
    }

    /// @notice Tests that admin can enable fast redeem
    function test_setFastRedeemEnabled_whenAdmin_enables() public {
        vm.expectEmit(false, false, false, true);
        emit FastRedeemEnabledUpdated(true);

        vm.prank(admin);
        stakediTry.setFastRedeemEnabled(true);

        assertTrue(stakediTry.fastRedeemEnabled(), "Fast redeem should be enabled");
    }

    /// @notice Tests that admin can disable fast redeem
    function test_setFastRedeemEnabled_whenAdmin_disables() public {
        // First enable it
        vm.prank(admin);
        stakediTry.setFastRedeemEnabled(true);

        // Then disable
        vm.expectEmit(false, false, false, true);
        emit FastRedeemEnabledUpdated(false);

        vm.prank(admin);
        stakediTry.setFastRedeemEnabled(false);

        assertFalse(stakediTry.fastRedeemEnabled(), "Fast redeem should be disabled");
    }

    // ============================================
    // setFastRedeemFee Tests (4 tests)
    // ============================================

    /// @notice Tests that non-admin cannot set fee
    function test_setFastRedeemFee_whenCallerNotAdmin_reverts() public {
        vm.expectRevert();
        vm.prank(nonAdmin);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
    }

    /// @notice Tests that fee cannot exceed maximum
    function test_setFastRedeemFee_whenFeeExceedsMax_reverts() public {
        uint16 excessiveFee = stakediTry.MAX_FAST_REDEEM_FEE() + 1;

        vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.InvalidFastRedeemFee.selector));
        vm.prank(admin);
        stakediTry.setFastRedeemFee(excessiveFee);
    }

    /// @notice Tests that admin can set valid fee
    function test_setFastRedeemFee_whenValid_setsFee() public {
        uint16 maxFee = stakediTry.MAX_FAST_REDEEM_FEE();

        vm.expectEmit(false, false, false, true);
        emit FastRedeemFeeUpdated(maxFee, DEFAULT_FEE);

        vm.prank(admin);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);

        assertEq(stakediTry.fastRedeemFeeInBPS(), DEFAULT_FEE, "Fee should be set");
    }

    /// @notice Tests that fee can be updated
    function test_setFastRedeemFee_canBeUpdated() public {
        uint16 newFee = 1000; // 10%

        vm.prank(admin);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);

        vm.expectEmit(false, false, false, true);
        emit FastRedeemFeeUpdated(DEFAULT_FEE, newFee);

        vm.prank(admin);
        stakediTry.setFastRedeemFee(newFee);

        assertEq(stakediTry.fastRedeemFeeInBPS(), newFee, "Fee should be updated");
    }

    // ============================================
    // setFastRedeemTreasury Tests (3 tests)
    // ============================================

    /// @notice Tests that non-admin cannot set treasury
    function test_setFastRedeemTreasury_whenCallerNotAdmin_reverts() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectRevert();
        vm.prank(nonAdmin);
        stakediTry.setFastRedeemTreasury(newTreasury);
    }

    /// @notice Tests that treasury cannot be set to zero
    function test_setFastRedeemTreasury_whenZeroAddress_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.InvalidZeroAddress.selector));
        vm.prank(admin);
        stakediTry.setFastRedeemTreasury(address(0));
    }

    /// @notice Tests that admin can update treasury
    function test_setFastRedeemTreasury_whenValid_updatesTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.expectEmit(true, true, false, false);
        emit FastRedeemTreasuryUpdated(treasury, newTreasury);

        vm.prank(admin);
        stakediTry.setFastRedeemTreasury(newTreasury);

        assertEq(stakediTry.fastRedeemTreasury(), newTreasury, "Treasury should be updated");
    }

    // ============================================
    // fastRedeem Tests (10 tests)
    // ============================================

    /// @notice Tests that fast redeem reverts when cooldown is off
    function test_fastRedeem_whenCooldownOff_reverts() public {
        // Set cooldown to 0
        vm.prank(admin);
        stakediTry.setCooldownDuration(0);

        vm.expectRevert(abi.encodeWithSelector(IStakediTry.OperationNotAllowed.selector));
        vm.prank(user1);
        stakediTry.fastRedeem(100e18, user1, user1);
    }

    /// @notice Tests that fast redeem reverts when disabled
    function test_fastRedeem_whenDisabled_reverts() public {
        // User deposits
        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.FastRedeemDisabled.selector));
        vm.prank(user1);
        stakediTry.fastRedeem(100e18, user1, user1);
    }

    /// @notice Tests that fast redeem reverts when shares exceed balance
    function test_fastRedeem_whenExcessiveShares_reverts() public {
        // Enable fast redeem
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        vm.expectRevert(abi.encodeWithSelector(IStakediTryCooldown.ExcessiveRedeemAmount.selector));
        vm.prank(user1);
        stakediTry.fastRedeem(shares + 1, user1, user1);
    }

    /// @notice Tests successful fast redeem with fee
    function test_fastRedeem_whenValid_redeems() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        // Calculate expected amounts
        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * DEFAULT_FEE) / 10000;
        uint256 expectedNet = expectedAssets - expectedFee;

        // Fast redeem
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        // Assertions
        assertEq(netAssets, expectedNet, "Net assets should match");
        assertEq(iTryToken.balanceOf(user1), userBalanceBefore + expectedNet, "User should receive net assets");
        assertEq(iTryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury should receive fee");
        assertEq(stakediTry.balanceOf(user1), 0, "User shares should be burned");
    }

    /// @notice Tests that fast redeem emits event
    function test_fastRedeem_whenValid_emitsEvent() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * DEFAULT_FEE) / 10000;

        vm.expectEmit(true, true, false, true);
        emit FastRedeemed(user1, user1, shares, expectedAssets, expectedFee);

        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);
    }

    /// @notice Tests fast redeem with different receiver
    function test_fastRedeem_withDifferentReceiver() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 user2BalanceBefore = iTryToken.balanceOf(user2);
        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedNet = expectedAssets - (expectedAssets * DEFAULT_FEE) / 10000;

        // Fast redeem to user2
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user2, user1);

        assertEq(iTryToken.balanceOf(user2), user2BalanceBefore + expectedNet, "Receiver should get net assets");
    }

    /// @notice Tests that setting zero fee reverts
    function test_fastRedeem_setZeroFee_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.InvalidFastRedeemFee.selector));
        vm.prank(admin);
        stakediTry.setFastRedeemFee(0);
    }

    /// @notice Tests fast redeem with maximum fee
    function test_fastRedeem_withMaximumFee() public {
        uint16 maxFee = stakediTry.MAX_FAST_REDEEM_FEE();

        // Setup with max fee
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(maxFee);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * maxFee) / 10000;
        uint256 expectedNet = expectedAssets - expectedFee;

        // Fast redeem
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        assertEq(netAssets, expectedNet, "Net should be reduced by max fee");
    }

    /// @notice Tests that fast redeem reverts when it would violate MIN_SHARES
    function test_fastRedeem_whenWouldViolateMinShares_reverts() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User1 deposits to get exactly 1.5e18 shares (just above MIN_SHARES)
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1.5e18, user1);

        // Try to fast redeem all shares - this would leave 0 in vault temporarily during split withdraw
        // Actually, since we're redeeming ALL shares, totalSupply becomes 0 which is allowed
        // So we need a scenario where we DON'T redeem all, but what remains is < MIN_SHARES

        // Let's have user2 also deposit
        vm.prank(user2);
        stakediTry.deposit(0.3e18, user2);

        // Now total supply = 1.8e18
        // If user1 redeems their 1.5e18, remaining = 0.3e18 < MIN_SHARES (1e18)
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.MinSharesViolation.selector));
        vm.prank(user1);
        stakediTry.fastRedeem(shares, user1, user1);
    }

    /// @notice Tests fast redeem with allowance (owner != caller)
    function test_fastRedeem_withAllowance() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User1 deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        // User1 approves user2
        vm.prank(user1);
        stakediTry.approve(user2, shares);

        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedNet = expectedAssets - (expectedAssets * DEFAULT_FEE) / 10000;

        // User2 redeems on behalf of user1
        vm.prank(user2);
        uint256 netAssets = stakediTry.fastRedeem(shares, user2, user1);

        assertEq(netAssets, expectedNet, "Should work with allowance");
        assertEq(stakediTry.balanceOf(user1), 0, "Owner shares should be burned");
    }

    /// @notice Tests multiple fast redeems
    function test_fastRedeem_multipleRedeems() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 totalShares = stakediTry.deposit(1000e18, user1);

        uint256 firstRedeem = totalShares / 2;
        uint256 secondRedeem = totalShares - firstRedeem;

        // First redeem
        vm.prank(user1);
        stakediTry.fastRedeem(firstRedeem, user1, user1);

        assertEq(stakediTry.balanceOf(user1), secondRedeem, "Half shares should remain");

        // Second redeem
        vm.prank(user1);
        stakediTry.fastRedeem(secondRedeem, user1, user1);

        assertEq(stakediTry.balanceOf(user1), 0, "All shares should be redeemed");
    }

    // ============================================
    // fastWithdraw Tests (7 tests)
    // ============================================

    /// @notice Tests that fast redeem assets reverts when cooldown is off
    function test_fastWithdraw_whenCooldownOff_reverts() public {
        // Set cooldown to 0
        vm.prank(admin);
        stakediTry.setCooldownDuration(0);

        vm.expectRevert(abi.encodeWithSelector(IStakediTry.OperationNotAllowed.selector));
        vm.prank(user1);
        stakediTry.fastWithdraw(100e18, user1, user1);
    }

    /// @notice Tests that fast redeem assets reverts when disabled
    function test_fastWithdraw_whenDisabled_reverts() public {
        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.FastRedeemDisabled.selector));
        vm.prank(user1);
        stakediTry.fastWithdraw(100e18, user1, user1);
    }

    /// @notice Tests that fast redeem assets reverts when excessive
    function test_fastWithdraw_whenExcessiveAssets_reverts() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        uint256 maxWithdraw = stakediTry.maxWithdraw(user1);

        vm.expectRevert(abi.encodeWithSelector(IStakediTryCooldown.ExcessiveWithdrawAmount.selector));
        vm.prank(user1);
        stakediTry.fastWithdraw(maxWithdraw + 1, user1, user1);
    }

    /// @notice Tests successful fast redeem assets
    function test_fastWithdraw_whenValid_redeems() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        uint256 assetsToRedeem = 500e18;
        uint256 userBalanceBefore = iTryToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = iTryToken.balanceOf(treasury);

        uint256 expectedFee = (assetsToRedeem * DEFAULT_FEE) / 10000;
        uint256 expectedNet = assetsToRedeem - expectedFee;

        vm.prank(user1);
        uint256 sharesBurned = stakediTry.fastWithdraw(assetsToRedeem, user1, user1);

        assertGt(sharesBurned, 0, "Shares should be burned");
        assertEq(iTryToken.balanceOf(user1), userBalanceBefore + expectedNet, "User should receive net assets");
        assertEq(iTryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury should receive fee");
    }

    /// @notice Tests fast redeem assets emits event
    function test_fastWithdraw_whenValid_emitsEvent() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        uint256 assetsToRedeem = 500e18;
        uint256 expectedShares = stakediTry.previewWithdraw(assetsToRedeem);
        uint256 expectedFee = (assetsToRedeem * DEFAULT_FEE) / 10000;

        vm.expectEmit(true, true, false, true);
        emit FastRedeemed(user1, user1, expectedShares, assetsToRedeem, expectedFee);

        vm.prank(user1);
        stakediTry.fastWithdraw(assetsToRedeem, user1, user1);
    }

    /// @notice Tests fast redeem assets with different receiver
    function test_fastWithdraw_withDifferentReceiver() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        vm.prank(user1);
        stakediTry.deposit(1000e18, user1);

        uint256 assetsToRedeem = 500e18;
        uint256 user2BalanceBefore = iTryToken.balanceOf(user2);
        uint256 expectedNet = assetsToRedeem - (assetsToRedeem * DEFAULT_FEE) / 10000;

        vm.prank(user1);
        stakediTry.fastWithdraw(assetsToRedeem, user2, user1);

        assertEq(iTryToken.balanceOf(user2), user2BalanceBefore + expectedNet, "Receiver should get net assets");
    }

    /// @notice Tests that setting zero fee reverts (fastWithdraw)
    function test_fastWithdraw_setZeroFee_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IStakediTryFastRedeem.InvalidFastRedeemFee.selector));
        vm.prank(admin);
        stakediTry.setFastRedeemFee(0);
    }

    /// @notice Tests that fast redeem assets reverts when it would violate MIN_SHARES
    function test_fastWithdraw_whenWouldViolateMinShares_reverts() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User1 deposits 1.5e18
        vm.prank(user1);
        stakediTry.deposit(1.5e18, user1);

        // User2 deposits 0.3e18
        vm.prank(user2);
        stakediTry.deposit(0.3e18, user2);

        // Total supply = 1.8e18
        // If user1 redeems 1.5e18 assets, remaining = 0.3e18 < MIN_SHARES (1e18)
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.MinSharesViolation.selector));
        vm.prank(user1);
        stakediTry.fastWithdraw(1.5e18, user1, user1);
    }

    // ============================================
    // Integration Tests (2 tests)
    // ============================================

    /// @notice Tests that fast redeem and cooldown can coexist
    function test_integration_fastRedeemAndCooldownCoexist() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        // User deposits
        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 halfShares = shares / 2;

        // Fast redeem half
        vm.prank(user1);
        stakediTry.fastRedeem(halfShares, user1, user1);

        assertEq(stakediTry.balanceOf(user1), halfShares, "Half shares should remain");

        // Cooldown the other half
        vm.prank(user1);
        stakediTry.cooldownShares(halfShares);

        assertEq(stakediTry.balanceOf(user1), 0, "All shares should be processed");
    }

    /// @notice Tests fee updates don't affect in-flight transactions
    function test_integration_feeUpdatesDuringRedemption() public {
        // Setup
        vm.startPrank(admin);
        stakediTry.setFastRedeemEnabled(true);
        stakediTry.setFastRedeemFee(DEFAULT_FEE);
        vm.stopPrank();

        vm.prank(user1);
        uint256 shares = stakediTry.deposit(1000e18, user1);

        uint256 expectedAssets = stakediTry.previewRedeem(shares);
        uint256 expectedFee = (expectedAssets * DEFAULT_FEE) / 10000;
        uint256 expectedNet = expectedAssets - expectedFee;

        // Change fee mid-transaction (in same block this doesn't matter, but tests logic)
        vm.prank(admin);
        stakediTry.setFastRedeemFee(1000); // 10%

        // Redeem uses NEW fee
        vm.prank(user1);
        uint256 netAssets = stakediTry.fastRedeem(shares, user1, user1);

        // Should use the NEW 10% fee, not the old 5% fee
        uint256 newExpectedFee = (expectedAssets * 1000) / 10000;
        uint256 newExpectedNet = expectedAssets - newExpectedFee;

        assertEq(netAssets, newExpectedNet, "Should use current fee");
    }
}
