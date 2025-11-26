// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable func-name-mixedcase  */

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {iTry} from "../../src/token/iTRY/iTry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakediTryCrosschain} from "../../src/token/wiTRY/StakediTryCrosschain.sol";
import {IStakediTryCrosschain} from "../../src/token/wiTRY/interfaces/IStakediTryCrosschain.sol";
import {IStakediTry} from "../../src/token/wiTRY/interfaces/IStakediTry.sol";
import {IStakediTryCooldown} from "../../src/token/wiTRY/interfaces/IStakediTryCooldown.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakediTryCrosschainTest
 * @notice Comprehensive unit tests for StakediTryCrosschain contract
 * @dev Tests composer-specific cooldown functionality with role-based access control
 */
contract StakediTryCrosschainTest is Test {
    iTry public itryToken;
    iTry public itryImplementation;
    ERC1967Proxy public itryProxy;
    StakediTryCrosschain public vault;

    address public owner;
    address public rewarder;
    address public treasury;
    address public alice;
    address public bob;
    address public vaultComposer;
    address public unauthorizedComposer;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public COMPOSER_ROLE;

    // Events
    event ComposerCooldownInitiated(
        address indexed composer, address indexed redeemer, uint256 shares, uint256 assets, uint104 cooldownEnd
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        // Setup test accounts
        owner = makeAddr("owner");
        rewarder = makeAddr("rewarder");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        vaultComposer = makeAddr("vaultComposer");
        unauthorizedComposer = makeAddr("unauthorizedComposer");

        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");
        vm.label(treasury, "treasury");
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(vaultComposer, "vaultComposer");
        vm.label(unauthorizedComposer, "unauthorizedComposer");

        // Deploy iTry implementation
        itryImplementation = new iTry();

        // Deploy iTry proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            iTry.initialize.selector,
            owner, // admin
            owner // initial minter
        );
        itryProxy = new ERC1967Proxy(address(itryImplementation), initData);
        itryToken = iTry(address(itryProxy));

        // Deploy StakediTryCrosschain
        vm.prank(owner);
        vault = new StakediTryCrosschain(IERC20(address(itryToken)), rewarder, owner, treasury);

        // Cache COMPOSER_ROLE
        COMPOSER_ROLE = vault.COMPOSER_ROLE();
    }

    // ============================================================================
    // Constructor & Setup Tests
    // ============================================================================

    function test_constructor() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.cooldownDuration(), vault.MAX_COOLDOWN_DURATION());
        assertTrue(address(vault.silo()) != address(0));
        assertEq(COMPOSER_ROLE, keccak256("COMPOSER_ROLE"));
    }

    function test_COMPOSER_ROLE_getter() public view {
        bytes32 role = vault.COMPOSER_ROLE();
        assertEq(role, keccak256("COMPOSER_ROLE"));
    }

    // ============================================================================
    // Role Management Tests - Using AccessControl directly
    // ============================================================================

    function test_grantComposerRole() public {
        assertFalse(vault.hasRole(COMPOSER_ROLE, vaultComposer));

        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        assertTrue(vault.hasRole(COMPOSER_ROLE, vaultComposer));
    }

    function test_grantComposerRole_revertsIfNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
    }

    function test_revokeComposerRole() public {
        // Grant role first
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        assertTrue(vault.hasRole(COMPOSER_ROLE, vaultComposer));

        // Revoke role
        vm.prank(owner);
        vault.revokeRole(COMPOSER_ROLE, vaultComposer);
        assertFalse(vault.hasRole(COMPOSER_ROLE, vaultComposer));
    }

    function test_revokeComposerRole_revertsIfNotAdmin() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        vm.prank(alice);
        vm.expectRevert();
        vault.revokeRole(COMPOSER_ROLE, vaultComposer);
    }

    function test_isComposer_returnsFalseForNonComposer() public view {
        assertFalse(vault.hasRole(COMPOSER_ROLE, alice));
        assertFalse(vault.hasRole(COMPOSER_ROLE, bob));
        assertFalse(vault.hasRole(COMPOSER_ROLE, vaultComposer));
    }

    // ============================================================================
    // Composer Cooldown Tests - Happy Path
    // ============================================================================

    function test_cooldownSharesByComposer_success() public {
        // Setup: Grant composer role and give composer shares
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        uint256 depositAmount = 100e18;
        _mintAndDeposit(vaultComposer, depositAmount);

        uint256 cooldownShares = 50e18;
        uint256 expectedAssets = vault.previewRedeem(cooldownShares);

        // Record initial state
        uint256 composerBalanceBefore = vault.balanceOf(vaultComposer);
        (uint104 aliceCooldownEndBefore, uint256 aliceAmountBefore) = vault.cooldowns(alice);
        assertEq(aliceCooldownEndBefore, 0);
        assertEq(aliceAmountBefore, 0);

        // Execute cooldown
        vm.prank(vaultComposer);
        uint256 returnedAssets = vault.cooldownSharesByComposer(cooldownShares, alice);

        // Verify return value
        assertEq(returnedAssets, expectedAssets);

        // Verify composer's shares were burned
        assertEq(vault.balanceOf(vaultComposer), composerBalanceBefore - cooldownShares);

        // Verify cooldown tracked in alice's account
        (uint104 aliceCooldownEnd, uint256 aliceAmount) = vault.cooldowns(alice);
        assertEq(aliceAmount, expectedAssets);
        assertEq(aliceCooldownEnd, block.timestamp + vault.cooldownDuration());
    }

    function test_cooldownAssetsByComposer_success() public {
        // Setup: Grant composer role and give composer shares
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        uint256 depositAmount = 100e18;
        _mintAndDeposit(vaultComposer, depositAmount);

        uint256 cooldownAssets = 50e18;
        uint256 expectedShares = vault.previewWithdraw(cooldownAssets);

        // Record initial state
        uint256 composerBalanceBefore = vault.balanceOf(vaultComposer);

        // Execute cooldown
        vm.prank(vaultComposer);
        uint256 returnedShares = vault.cooldownAssetsByComposer(cooldownAssets, bob);

        // Verify return value
        assertEq(returnedShares, expectedShares);

        // Verify composer's shares were burned
        assertEq(vault.balanceOf(vaultComposer), composerBalanceBefore - expectedShares);

        // Verify cooldown tracked in bob's account
        (uint104 bobCooldownEnd, uint256 bobAmount) = vault.cooldowns(bob);
        assertEq(bobAmount, cooldownAssets);
        assertEq(bobCooldownEnd, block.timestamp + vault.cooldownDuration());
    }

    function test_cooldownSharesByComposer_multipleCooldownsAccumulate() public {
        // Setup
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 200e18);

        // First cooldown
        vm.prank(vaultComposer);
        uint256 assets1 = vault.cooldownSharesByComposer(50e18, alice);

        (uint104 cooldownEnd1, uint256 amount1) = vault.cooldowns(alice);
        assertEq(amount1, assets1);

        // Fast forward time (but not past cooldown)
        vm.warp(block.timestamp + 30 days);

        // Second cooldown (should overwrite timestamp but accumulate assets)
        vm.prank(vaultComposer);
        uint256 assets2 = vault.cooldownSharesByComposer(50e18, alice);

        (uint104 cooldownEnd2, uint256 amount2) = vault.cooldowns(alice);
        assertEq(amount2, assets1 + assets2); // Assets accumulate
        assertGt(cooldownEnd2, cooldownEnd1); // Timestamp updates (overwrites)
    }

    // ============================================================================
    // Redeemer Can Claim After Cooldown
    // ============================================================================

    function test_redeemerCanUnstakeAfterCooldown() public {
        // Setup
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        // Initiate cooldown
        vm.prank(vaultComposer);
        uint256 assets = vault.cooldownSharesByComposer(100e18, alice);

        // Verify alice can't unstake before cooldown
        vm.prank(alice);
        vm.expectRevert(IStakediTryCooldown.InvalidCooldown.selector);
        vault.unstake(alice);

        // Fast forward past cooldown period
        vm.warp(block.timestamp + vault.cooldownDuration() + 1);

        // Alice can now unstake
        uint256 aliceBalanceBefore = itryToken.balanceOf(alice);
        vm.prank(alice);
        vault.unstake(alice);

        // Verify alice received assets
        assertEq(itryToken.balanceOf(alice), aliceBalanceBefore + assets);

        // Verify cooldown cleared
        (uint104 cooldownEnd, uint256 amount) = vault.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(amount, 0);
    }

    function test_redeemerCanUnstakeToAnyReceiver() public {
        // Setup
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        uint256 assets = vault.cooldownSharesByComposer(100e18, alice);

        vm.warp(block.timestamp + vault.cooldownDuration() + 1);

        // Alice unstakes to bob's address
        uint256 bobBalanceBefore = itryToken.balanceOf(bob);
        vm.prank(alice);
        vault.unstake(bob);

        assertEq(itryToken.balanceOf(bob), bobBalanceBefore + assets);
    }

    // ============================================================================
    // Access Control Tests
    // ============================================================================

    function test_cooldownSharesByComposer_revertsIfNotComposer() public {
        // Give alice shares but not composer role
        _mintAndDeposit(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(); // AccessControl will revert with role error
        vault.cooldownSharesByComposer(50e18, bob);
    }

    function test_cooldownAssetsByComposer_revertsIfNotComposer() public {
        _mintAndDeposit(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert(); // AccessControl will revert with role error
        vault.cooldownAssetsByComposer(50e18, bob);
    }

    // ============================================================================
    // Validation Tests
    // ============================================================================

    function test_cooldownSharesByComposer_revertsIfInvalidRedeemer() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTry.InvalidZeroAddress.selector);
        vault.cooldownSharesByComposer(50e18, address(0));
    }

    function test_cooldownAssetsByComposer_revertsIfInvalidRedeemer() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTry.InvalidZeroAddress.selector);
        vault.cooldownAssetsByComposer(50e18, address(0));
    }

    function test_cooldownSharesByComposer_revertsIfInsufficientShares() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTryCooldown.ExcessiveRedeemAmount.selector);
        vault.cooldownSharesByComposer(200e18, alice); // More than balance
    }

    function test_cooldownAssetsByComposer_revertsIfInsufficientAssets() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTryCooldown.ExcessiveWithdrawAmount.selector);
        vault.cooldownAssetsByComposer(200e18, alice); // More than max withdraw
    }

    function test_cooldownSharesByComposer_revertsIfCooldownDisabled() public {
        // Disable cooldown
        vm.prank(owner);
        vault.setCooldownDuration(0);

        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTry.OperationNotAllowed.selector);
        vault.cooldownSharesByComposer(50e18, alice);
    }

    function test_cooldownAssetsByComposer_revertsIfCooldownDisabled() public {
        // Disable cooldown
        vm.prank(owner);
        vault.setCooldownDuration(0);

        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTry.OperationNotAllowed.selector);
        vault.cooldownAssetsByComposer(50e18, alice);
    }

    // ============================================================================
    // Standard Functions Still Work
    // ============================================================================

    function test_standardCooldownShares_stillWorks() public {
        // Regular user with shares
        _mintAndDeposit(bob, 50e18);

        vm.prank(bob);
        uint256 assets = vault.cooldownShares(25e18);

        // Verify works as expected (standard behavior)
        (uint104 cooldownEnd, uint256 amount) = vault.cooldowns(bob);
        assertEq(amount, assets);
        assertEq(cooldownEnd, block.timestamp + vault.cooldownDuration());
    }

    function test_standardCooldownAssets_stillWorks() public {
        _mintAndDeposit(bob, 50e18);

        vm.prank(bob);
        uint256 shares = vault.cooldownAssets(25e18);

        (uint104 cooldownEnd, uint256 amount) = vault.cooldowns(bob);
        assertEq(amount, 25e18);
        assertGt(shares, 0);
    }

    function test_composerFunctionsDoNotAffectStandardUsers() public {
        // Setup composer
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);
        _mintAndDeposit(vaultComposer, 100e18);

        // Setup regular user
        _mintAndDeposit(bob, 50e18);

        // Composer does composer cooldown
        vm.prank(vaultComposer);
        vault.cooldownSharesByComposer(50e18, alice);

        // Bob can still do standard cooldown
        vm.prank(bob);
        vault.cooldownShares(25e18);

        // Verify both cooldowns exist independently
        (uint104 aliceCooldownEnd, uint256 aliceAmount) = vault.cooldowns(alice);
        (uint104 bobCooldownEnd, uint256 bobAmount) = vault.cooldowns(bob);

        assertGt(aliceAmount, 0);
        assertGt(bobAmount, 0);
        assertEq(aliceCooldownEnd, bobCooldownEnd); // Same timestamp as initiated same block
    }

    // ============================================================================
    // Edge Cases Tests
    // ============================================================================

    function test_multipleComposers_canCooldownForSameRedeemer() public {
        address composer1 = vaultComposer;
        address composer2 = makeAddr("composer2");

        // Grant roles to both composers
        vm.startPrank(owner);
        vault.grantRole(COMPOSER_ROLE, composer1);
        vault.grantRole(COMPOSER_ROLE, composer2);
        vm.stopPrank();

        // Give shares to both
        _mintAndDeposit(composer1, 100e18);
        _mintAndDeposit(composer2, 100e18);

        // First composer initiates cooldown
        vm.prank(composer1);
        uint256 assets1 = vault.cooldownSharesByComposer(50e18, alice);

        // Second composer initiates cooldown for same redeemer
        vm.prank(composer2);
        uint256 assets2 = vault.cooldownSharesByComposer(50e18, alice);

        // Assets should accumulate
        (uint104 cooldownEnd, uint256 totalAmount) = vault.cooldowns(alice);
        assertEq(totalAmount, assets1 + assets2);
    }

    // ============================================================================
    // unstakeThroughComposer Tests
    // ============================================================================

    function test_unstakeThroughComposer_success() public {
        // Setup: Grant composer role and create cooldown
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        _mintAndDeposit(vaultComposer, 100e18);

        // Initiate cooldown
        vm.prank(vaultComposer);
        uint256 expectedAssets = vault.cooldownSharesByComposer(100e18, alice);

        // Fast forward past cooldown
        vm.warp(block.timestamp + vault.cooldownDuration() + 1);

        // Unstake through composer
        uint256 composerBalanceBefore = itryToken.balanceOf(vaultComposer);
        vm.prank(vaultComposer);
        uint256 returnedAssets = vault.unstakeThroughComposer(alice);

        // Verify return value
        assertEq(returnedAssets, expectedAssets);

        // Verify composer received assets
        assertEq(itryToken.balanceOf(vaultComposer), composerBalanceBefore + expectedAssets);

        // Verify cooldown cleared
        (uint104 cooldownEnd, uint256 amount) = vault.cooldowns(alice);
        assertEq(cooldownEnd, 0);
        assertEq(amount, 0);
    }

    function test_unstakeThroughComposer_revertsWhenCooldownNotReady() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        _mintAndDeposit(vaultComposer, 100e18);

        // Initiate cooldown
        vm.prank(vaultComposer);
        vault.cooldownSharesByComposer(100e18, alice);

        // Try to unstake before cooldown complete
        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTryCooldown.InvalidCooldown.selector);
        vault.unstakeThroughComposer(alice);
    }

    function test_unstakeThroughComposer_revertsWhenCooldownNotReady_explicitTiming() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        _mintAndDeposit(vaultComposer, 100e18);

        // Initiate cooldown
        vm.prank(vaultComposer);
        vault.cooldownSharesByComposer(100e18, alice);

        // Get cooldown info
        (uint104 cooldownEnd, uint256 underlyingAmount) = vault.cooldowns(alice);
        assertGt(cooldownEnd, block.timestamp, "Cooldown should be in future");
        assertEq(underlyingAmount, 100e18, "Underlying amount should match");

        // Warp to just before cooldown ends (1 second before)
        vm.warp(cooldownEnd - 1);
        assertLt(block.timestamp, cooldownEnd, "Should still be before cooldown end");

        // Try to unstake - should fail because cooldown not complete
        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTryCooldown.InvalidCooldown.selector);
        vault.unstakeThroughComposer(alice);
    }

    function test_unstakeThroughComposer_revertsAsNonComposer() public {
        // alice is not a composer
        assertFalse(vault.hasRole(COMPOSER_ROLE, alice));

        // Would revert with access control error
        vm.prank(alice);
        vm.expectRevert();
        vault.unstakeThroughComposer(alice);
    }

    function test_unstakeThroughComposer_revertsWithInvalidReceiver() public {
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, vaultComposer);

        // Would revert with InvalidZeroAddress
        vm.prank(vaultComposer);
        vm.expectRevert(IStakediTry.InvalidZeroAddress.selector);
        vault.unstakeThroughComposer(address(0));
    }

    // ============================================================================
    // Helper Functions
    // ============================================================================

    function _mintAndDeposit(address user, uint256 amount) internal {
        vm.prank(owner);
        itryToken.mint(user, amount);

        vm.startPrank(user);
        itryToken.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }
}
