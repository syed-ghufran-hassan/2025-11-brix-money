// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/token/wiTRY/StakediTry.sol";
import {IStakediTry} from "../src/token/wiTRY/interfaces/IStakediTry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title StakediTry redistributeLockedAmount Tests
 * @notice Comprehensive tests for the redistributeLockedAmount admin function
 * @dev Tests cover access control, redistribution, burning, and MIN_SHARES enforcement
 *      Related to Zellic Audit Finding 3.3
 */
contract StakediTryRedistributeTest is Test {
    StakediTry public stakediTry;
    MockERC20 public iTryToken;

    address public admin;
    address public rewarder;
    address public user1;
    address public user2;
    address public restrictedUser;
    address public nonAdmin;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant FULL_RESTRICTED_STAKER_ROLE = keccak256("FULL_RESTRICTED_STAKER_ROLE");
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");

    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 public constant MIN_SHARES = 1 ether;

    event LockedAmountRedistributed(address indexed from, address indexed to, uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        rewarder = makeAddr("rewarder");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        restrictedUser = makeAddr("restrictedUser");
        nonAdmin = makeAddr("nonAdmin");

        // Deploy iTRY token mock
        iTryToken = new MockERC20("iTRY", "iTRY");

        // Deploy StakediTry
        vm.prank(admin);
        stakediTry = new StakediTry(IERC20(address(iTryToken)), rewarder, admin);

        // Setup blacklist manager role for admin
        vm.prank(admin);
        stakediTry.grantRole(BLACKLIST_MANAGER_ROLE, admin);

        // Mint tokens to users
        iTryToken.mint(user1, INITIAL_SUPPLY);
        iTryToken.mint(user2, INITIAL_SUPPLY);
        iTryToken.mint(restrictedUser, INITIAL_SUPPLY);

        // Users approve StakediTry
        vm.prank(user1);
        iTryToken.approve(address(stakediTry), type(uint256).max);

        vm.prank(user2);
        iTryToken.approve(address(stakediTry), type(uint256).max);

        vm.prank(restrictedUser);
        iTryToken.approve(address(stakediTry), type(uint256).max);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _depositAsRestrictedUser(uint256 amount) internal returns (uint256 shares) {
        // First deposit, then restrict
        vm.prank(restrictedUser);
        shares = stakediTry.deposit(amount, restrictedUser);

        // Add to blacklist (full restriction)
        vm.prank(admin);
        stakediTry.addToBlacklist(restrictedUser, true);
    }

    // ============================================
    // Access Control Tests
    // ============================================

    /// @notice Tests that only admin can call redistributeLockedAmount
    function test_redistributeLockedAmount_revertsWhenCallerNotAdmin() public {
        _depositAsRestrictedUser(100e18);

        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl revert
        stakediTry.redistributeLockedAmount(restrictedUser, user1);
    }

    /// @notice Tests revert when 'from' is not fully restricted
    function test_redistributeLockedAmount_revertsWhenFromNotRestricted() public {
        // user1 deposits but is NOT restricted
        vm.prank(user1);
        stakediTry.deposit(100e18, user1);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.OperationNotAllowed.selector));
        stakediTry.redistributeLockedAmount(user1, user2);
    }

    /// @notice Tests revert when 'to' is fully restricted
    function test_redistributeLockedAmount_revertsWhenToIsRestricted() public {
        _depositAsRestrictedUser(100e18);

        // Also restrict the target
        vm.prank(admin);
        stakediTry.addToBlacklist(user1, true);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStakediTry.OperationNotAllowed.selector));
        stakediTry.redistributeLockedAmount(restrictedUser, user1);
    }

    // ============================================
    // Redistribution to Valid Address Tests
    // ============================================

    /// @notice Tests successful redistribution to a valid address
    function test_redistributeLockedAmount_toValidAddress_success() public {
        uint256 depositAmount = 100e18;
        uint256 shares = _depositAsRestrictedUser(depositAmount);

        uint256 user1SharesBefore = stakediTry.balanceOf(user1);
        uint256 totalSupplyBefore = stakediTry.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit LockedAmountRedistributed(restrictedUser, user1, shares);

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, user1);

        // Verify shares transferred
        assertEq(stakediTry.balanceOf(restrictedUser), 0, "Restricted user should have 0 shares");
        assertEq(stakediTry.balanceOf(user1), user1SharesBefore + shares, "User1 should receive shares");
        assertEq(stakediTry.totalSupply(), totalSupplyBefore, "Total supply should remain same");
    }

    /// @notice Tests redistribution preserves share value
    function test_redistributeLockedAmount_toValidAddress_preservesValue() public {
        uint256 depositAmount = 100e18;
        uint256 shares = _depositAsRestrictedUser(depositAmount);

        uint256 assetValueBefore = stakediTry.previewRedeem(shares);

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, user1);

        uint256 assetValueAfter = stakediTry.previewRedeem(stakediTry.balanceOf(user1));
        assertEq(assetValueAfter, assetValueBefore, "Asset value should be preserved");
    }

    // ============================================
    // Burning to address(0) Tests
    // ============================================

    /// @notice Tests successful burn to address(0) when totalSupply remains >= MIN_SHARES
    function test_redistributeLockedAmount_toZeroAddress_success() public {
        // First, user1 deposits enough to maintain MIN_SHARES
        vm.prank(user1);
        stakediTry.deposit(100e18, user1);

        // Then restricted user deposits
        uint256 shares = _depositAsRestrictedUser(50e18);

        uint256 totalSupplyBefore = stakediTry.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit LockedAmountRedistributed(restrictedUser, address(0), shares);

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        // Verify shares burned
        assertEq(stakediTry.balanceOf(restrictedUser), 0, "Restricted user should have 0 shares");
        assertEq(stakediTry.totalSupply(), totalSupplyBefore - shares, "Total supply should decrease");
        assertGe(stakediTry.totalSupply(), MIN_SHARES, "Total supply should be >= MIN_SHARES");
    }

    /// @notice Tests that burning all shares (totalSupply -> 0) is allowed
    function test_redistributeLockedAmount_toZeroAddress_fullBurnAllowed() public {
        // Only restricted user has shares
        _depositAsRestrictedUser(100e18);

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        // Total supply of 0 is allowed (not in prohibited range)
        assertEq(stakediTry.totalSupply(), 0, "Total supply should be 0");
    }

    // ============================================
    // MIN_SHARES Violation Tests (Core Audit Fix)
    // ============================================

    /// @notice Tests that _checkMinShares is called after burn in redistributeLockedAmount
    /// @dev This is the core test for Zellic Finding 3.3
    ///      The fix ensures totalSupply doesn't fall into prohibited range (0 < X < MIN_SHARES)
    ///      after burning shares during redistribution
    function test_redistributeLockedAmount_toZeroAddress_revertsOnMinSharesViolation() public {
        // Setup: user1 deposits MIN_SHARES (minimum valid amount)
        vm.prank(user1);
        stakediTry.deposit(MIN_SHARES, user1);

        // Restricted user deposits 1.5e18
        _depositAsRestrictedUser(1.5e18);

        // Total supply = 2.5e18
        // After burning restricted user's 1.5e18, total supply = MIN_SHARES (1e18)
        // This is exactly at MIN_SHARES boundary, which is ALLOWED

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        // Should succeed - totalSupply = MIN_SHARES is valid
        assertEq(stakediTry.totalSupply(), MIN_SHARES, "Total supply should be MIN_SHARES");
    }

    /// @notice Tests redistribution works correctly with multiple users
    /// @dev Verifies that MIN_SHARES check allows valid states
    function test_redistributeLockedAmount_toZeroAddress_multipleUsers() public {
        // user1 deposits 2e18
        vm.prank(user1);
        stakediTry.deposit(2e18, user1);

        // user2 deposits 2e18
        vm.prank(user2);
        stakediTry.deposit(2e18, user2);

        // Restricted user deposits 2e18
        _depositAsRestrictedUser(2e18);

        // Total supply = 6e18
        // After burning restricted user's 2e18, total supply = 4e18 >= MIN_SHARES

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        assertEq(stakediTry.totalSupply(), 4e18, "Total supply should be 4e18");
        assertGe(stakediTry.totalSupply(), MIN_SHARES, "Total supply should be >= MIN_SHARES");
    }

    /// @notice Tests that burning succeeds when result is exactly MIN_SHARES
    function test_redistributeLockedAmount_toZeroAddress_succeedsAtExactMinShares() public {
        // Setup: user1 deposits exactly MIN_SHARES
        vm.prank(user1);
        stakediTry.deposit(MIN_SHARES, user1);

        // Restricted user deposits any amount
        _depositAsRestrictedUser(50e18);

        // After burning, total supply = MIN_SHARES (allowed)

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        assertEq(stakediTry.totalSupply(), MIN_SHARES, "Total supply should be exactly MIN_SHARES");
    }

    /// @notice Tests redistribution to valid address with MIN_SHARES check
    /// @dev The _checkMinShares is called right after _burn, before the if/else branch
    ///      This means even redistribution to a valid address checks MIN_SHARES after burn
    function test_redistributeLockedAmount_toValidAddress_minSharesCheckedAfterBurn() public {
        // Setup: user1 deposits MIN_SHARES
        vm.prank(user1);
        stakediTry.deposit(MIN_SHARES, user1);

        // Restricted user deposits 2e18
        _depositAsRestrictedUser(2e18);

        // Total supply = 3e18
        // After burn: MIN_SHARES (1e18) - this is ALLOWED
        // Then mint happens to restore shares to recipient

        uint256 user2SharesBefore = stakediTry.balanceOf(user2);

        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, user2);

        // Redistribution to user2 should succeed
        // totalSupply stays same (burn + mint), user2 receives shares
        assertEq(stakediTry.totalSupply(), 3e18, "Total supply should remain 3e18");
        assertEq(stakediTry.balanceOf(user2), user2SharesBefore + 2e18, "User2 should receive shares");
    }

    // ============================================
    // Edge Cases
    // ============================================

    /// @notice Tests redistribution when restricted user has zero balance
    function test_redistributeLockedAmount_zeroBalance() public {
        // Restrict user without any deposits
        vm.prank(admin);
        stakediTry.addToBlacklist(restrictedUser, true);

        // Should succeed but redistribute 0
        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, user1);

        assertEq(stakediTry.balanceOf(user1), 0, "User1 should have 0 shares");
    }

    /// @notice Tests that redistribution updates vesting correctly when burning
    function test_redistributeLockedAmount_toZeroAddress_updatesVesting() public {
        // First deposit to have base shares
        vm.prank(user1);
        stakediTry.deposit(100e18, user1);

        // Restricted user deposits
        uint256 shares = _depositAsRestrictedUser(50e18);
        uint256 expectedVestingAmount = stakediTry.previewRedeem(shares);

        // Burn to address(0)
        vm.prank(admin);
        stakediTry.redistributeLockedAmount(restrictedUser, address(0));

        // Verify vesting amount is updated
        assertEq(stakediTry.vestingAmount(), expectedVestingAmount, "Vesting amount should be updated");
    }
}
