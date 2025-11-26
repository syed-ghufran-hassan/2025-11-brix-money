// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable func-name-mixedcase  */

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";

import {iTry} from "../src/token/iTRY/iTry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakediTryCrosschain} from "../src/token/wiTRY/StakediTryCrosschain.sol";
import {IStakediTryCrosschain} from "../src/token/wiTRY/interfaces/IStakediTryCrosschain.sol";
import {IStakediTry} from "../src/token/wiTRY/interfaces/IStakediTry.sol";
import {IStakediTryCooldown} from "../src/token/wiTRY/interfaces/IStakediTryCooldown.sol";
import {IStakediTryFastRedeem} from "../src/token/wiTRY/interfaces/IStakediTryFastRedeem.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakediTryCrosschainFastRedeemTest
 * @notice Comprehensive unit tests for StakediTryCrosschain fast redeem functionality
 * @dev Tests fastRedeemThroughComposer and fastWithdrawThroughComposer functions
 */
contract StakediTryCrosschainFastRedeemTest is Test {
    iTry public itryToken;
    iTry public itryImplementation;
    ERC1967Proxy public itryProxy;
    StakediTryCrosschain public vault;

    address public owner;
    address public rewarder;
    address public treasury;
    address public composer;
    address public crosschainReceiver;
    address public unauthorizedUser;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public COMPOSER_ROLE;

    // Events
    event FastRedeemedThroughComposer(
        address indexed composer,
        address indexed crosschainReceiver,
        address indexed owner,
        uint256 shares,
        uint256 assets,
        uint256 feeAssets
    );

    function setUp() public {
        // Setup test accounts
        owner = makeAddr("owner");
        rewarder = makeAddr("rewarder");
        treasury = makeAddr("treasury");
        composer = makeAddr("Composer");
        crosschainReceiver = makeAddr("CrosschainReceiver");
        unauthorizedUser = makeAddr("unauthorizedUser");

        vm.label(owner, "owner");
        vm.label(rewarder, "rewarder");
        vm.label(treasury, "treasury");
        vm.label(composer, "Composer");
        vm.label(crosschainReceiver, "CrosschainReceiver");
        vm.label(unauthorizedUser, "unauthorizedUser");

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

        // Grant composer role to composer address
        vm.prank(owner);
        vault.grantRole(COMPOSER_ROLE, composer);

        // Enable fast redeem functionality
        vm.prank(owner);
        vault.setFastRedeemEnabled(true);

        // Set a reasonable fast redeem fee (10% = 1000 BPS)
        vm.prank(owner);
        vault.setFastRedeemFee(1000);
    }

    // ============================================================================
    // Phase 1: Access Control & Input Validation (6 tests)
    // ============================================================================

    function test_fastRedeemThroughComposer_revertsIfNotComposer() public {
        // Give unauthorized user shares but not composer role
        _mintAndDeposit(unauthorizedUser, 100e18);

        vm.prank(unauthorizedUser);
        vm.expectRevert(); // AccessControl will revert
        vault.fastRedeemThroughComposer(50e18, crosschainReceiver, unauthorizedUser);
    }

    function test_fastWithdrawThroughComposer_revertsIfNotComposer() public {
        // Give unauthorized user shares but not composer role
        _mintAndDeposit(unauthorizedUser, 100e18);

        vm.prank(unauthorizedUser);
        vm.expectRevert(); // AccessControl will revert
        vault.fastWithdrawThroughComposer(50e18, crosschainReceiver, unauthorizedUser);
    }

    function test_fastRedeemThroughComposer_revertsWithZeroCrosschainReceiver() public {
        _mintAndDeposit(composer, 100e18);

        vm.prank(composer);
        vm.expectRevert(IStakediTry.InvalidZeroAddress.selector);
        vault.fastRedeemThroughComposer(50e18, address(0), composer);
    }

    function test_fastWithdrawThroughComposer_revertsWithZeroCrosschainReceiver() public {
        _mintAndDeposit(composer, 100e18);

        vm.prank(composer);
        vm.expectRevert(IStakediTry.InvalidZeroAddress.selector);
        vault.fastWithdrawThroughComposer(50e18, address(0), composer);
    }

    function test_fastRedeemThroughComposer_revertsWithExcessiveShares() public {
        _mintAndDeposit(composer, 100e18);

        vm.prank(composer);
        vm.expectRevert(IStakediTryCooldown.ExcessiveRedeemAmount.selector);
        vault.fastRedeemThroughComposer(200e18, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_revertsWithExcessiveAssets() public {
        _mintAndDeposit(composer, 100e18);

        uint256 maxWithdraw = vault.maxWithdraw(composer);

        vm.prank(composer);
        vm.expectRevert(IStakediTryCooldown.ExcessiveWithdrawAmount.selector);
        vault.fastWithdrawThroughComposer(maxWithdraw + 1e18, crosschainReceiver, composer);
    }

    // ============================================================================
    // Phase 2: Core Functionality (12 tests)
    // ============================================================================

    function test_fastRedeemThroughComposer_burnsSharesAndTransfersAssets() public {
        uint256 depositAmount = 100e18;
        _mintAndDeposit(composer, depositAmount);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);

        uint256 composerSharesBefore = vault.balanceOf(composer);
        uint256 composerAssetsBefore = itryToken.balanceOf(composer);

        vm.prank(composer);
        uint256 returnedAssets = vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        // Verify shares were burned
        assertEq(vault.balanceOf(composer), composerSharesBefore - sharesToRedeem, "Shares not burned correctly");

        // Verify assets were transferred to composer (after fee)
        uint256 feeAssets = (expectedTotalAssets * 1000) / 10000; // 10% fee
        uint256 netAssets = expectedTotalAssets - feeAssets;
        assertEq(returnedAssets, netAssets, "Returned assets incorrect");
        assertEq(itryToken.balanceOf(composer), composerAssetsBefore + netAssets, "Assets not transferred to composer");
    }

    function test_fastRedeemThroughComposer_calculatesFeesCorrectly() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000; // 10% fee
        uint256 expectedNetAssets = expectedTotalAssets - expectedFee;

        uint256 treasuryBalanceBefore = itryToken.balanceOf(treasury);

        vm.prank(composer);
        uint256 returnedAssets = vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        // Verify fee calculation
        assertEq(returnedAssets, expectedNetAssets, "Net assets calculation incorrect");

        // Verify treasury received fee
        assertEq(itryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury didn't receive correct fee");
    }

    function test_fastRedeemThroughComposer_emitsCorrectEvent() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFee;

        vm.expectEmit(true, true, true, true);
        emit FastRedeemedThroughComposer(composer, crosschainReceiver, composer, sharesToRedeem, expectedNetAssets, expectedFee);

        vm.prank(composer);
        vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_convertsAssetsToSharesAndBurns() public {
        uint256 depositAmount = 100e18;
        _mintAndDeposit(composer, depositAmount);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedShares = vault.previewWithdraw(assetsToWithdraw);

        uint256 composerSharesBefore = vault.balanceOf(composer);
        uint256 composerAssetsBefore = itryToken.balanceOf(composer);

        vm.prank(composer);
        uint256 returnedShares = vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        // Verify shares were burned
        assertEq(returnedShares, expectedShares, "Returned shares incorrect");
        assertEq(vault.balanceOf(composer), composerSharesBefore - expectedShares, "Shares not burned correctly");

        // Verify assets were transferred (after fee)
        uint256 feeAssets = (assetsToWithdraw * 1000) / 10000; // 10% fee
        uint256 netAssets = assetsToWithdraw - feeAssets;
        assertEq(itryToken.balanceOf(composer), composerAssetsBefore + netAssets, "Assets not transferred correctly");
    }

    function test_fastWithdrawThroughComposer_calculatesFeesCorrectly() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedFee = (assetsToWithdraw * 1000) / 10000; // 10% fee
        uint256 expectedNetAssets = assetsToWithdraw - expectedFee;

        uint256 treasuryBalanceBefore = itryToken.balanceOf(treasury);
        uint256 composerAssetsBefore = itryToken.balanceOf(composer);

        vm.prank(composer);
        vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        // Verify net assets transferred to composer
        assertEq(itryToken.balanceOf(composer), composerAssetsBefore + expectedNetAssets, "Net assets incorrect");

        // Verify treasury received fee
        assertEq(itryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury fee incorrect");
    }

    function test_fastWithdrawThroughComposer_emitsCorrectEvent() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedShares = vault.previewWithdraw(assetsToWithdraw);
        uint256 expectedFee = (assetsToWithdraw * 1000) / 10000;
        uint256 expectedNetAssets = assetsToWithdraw - expectedFee;

        vm.expectEmit(true, true, true, true);
        emit FastRedeemedThroughComposer(composer, crosschainReceiver, composer, expectedShares, expectedNetAssets, expectedFee);

        vm.prank(composer);
        vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);
    }

    function test_fastRedeemThroughComposer_composerReceivesAssetsNotRedeemer() public {
        _mintAndDeposit(composer, 100e18);

        uint256 crosschainReceiverBalanceBefore = itryToken.balanceOf(crosschainReceiver);
        uint256 composerAssetsBefore = itryToken.balanceOf(composer);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFee;

        vm.prank(composer);
        vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        // Composer receives the assets (for crosschain transfer)
        assertEq(itryToken.balanceOf(composer), composerAssetsBefore + expectedNetAssets, "Composer should receive assets");

        // Crosschain receiver does NOT receive assets directly
        assertEq(itryToken.balanceOf(crosschainReceiver), crosschainReceiverBalanceBefore, "Crosschain receiver should not receive assets directly");
    }

    function test_fastWithdrawThroughComposer_composerReceivesAssetsNotRedeemer() public {
        _mintAndDeposit(composer, 100e18);

        uint256 crosschainReceiverBalanceBefore = itryToken.balanceOf(crosschainReceiver);
        uint256 composerAssetsBefore = itryToken.balanceOf(composer);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedFee = (assetsToWithdraw * 1000) / 10000;
        uint256 expectedNetAssets = assetsToWithdraw - expectedFee;

        vm.prank(composer);
        vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        // Composer receives the assets
        assertEq(itryToken.balanceOf(composer), composerAssetsBefore + expectedNetAssets, "Composer should receive assets");

        // Crosschain receiver does NOT receive assets directly
        assertEq(itryToken.balanceOf(crosschainReceiver), crosschainReceiverBalanceBefore, "Crosschain receiver should not receive assets directly");
    }

    function test_fastRedeemThroughComposer_transfersFeesToTreasury() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000;

        uint256 treasuryBalanceBefore = itryToken.balanceOf(treasury);

        vm.prank(composer);
        vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        // Verify treasury received exact fee amount
        assertEq(itryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury should receive exact fee");
    }

    function test_fastWithdrawThroughComposer_transfersFeesToTreasury() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedFee = (assetsToWithdraw * 1000) / 10000;

        uint256 treasuryBalanceBefore = itryToken.balanceOf(treasury);

        vm.prank(composer);
        vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        // Verify treasury received exact fee amount
        assertEq(itryToken.balanceOf(treasury), treasuryBalanceBefore + expectedFee, "Treasury should receive exact fee");
    }

    function test_fastRedeemThroughComposer_returnsCorrectAssets() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFee;

        vm.prank(composer);
        uint256 returnedAssets = vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        assertEq(returnedAssets, expectedNetAssets, "Should return net assets after fee");
    }

    function test_fastWithdrawThroughComposer_returnsCorrectShares() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedShares = vault.previewWithdraw(assetsToWithdraw);

        vm.prank(composer);
        uint256 returnedShares = vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        assertEq(returnedShares, expectedShares, "Should return correct shares");
    }

    // ============================================================================
    // Phase 3: State Dependencies & Edge Cases (9 tests)
    // ============================================================================

    function test_fastRedeemThroughComposer_revertsWhenCooldownDisabled() public {
        _mintAndDeposit(composer, 100e18);

        // Disable cooldown
        vm.prank(owner);
        vault.setCooldownDuration(0);

        vm.prank(composer);
        vm.expectRevert(IStakediTry.OperationNotAllowed.selector);
        vault.fastRedeemThroughComposer(50e18, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_revertsWhenCooldownDisabled() public {
        _mintAndDeposit(composer, 100e18);

        // Disable cooldown
        vm.prank(owner);
        vault.setCooldownDuration(0);

        vm.prank(composer);
        vm.expectRevert(IStakediTry.OperationNotAllowed.selector);
        vault.fastWithdrawThroughComposer(50e18, crosschainReceiver, composer);
    }

    function test_fastRedeemThroughComposer_revertsWhenFastRedeemDisabled() public {
        _mintAndDeposit(composer, 100e18);

        // Disable fast redeem
        vm.prank(owner);
        vault.setFastRedeemEnabled(false);

        vm.prank(composer);
        vm.expectRevert(IStakediTryFastRedeem.FastRedeemDisabled.selector);
        vault.fastRedeemThroughComposer(50e18, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_revertsWhenFastRedeemDisabled() public {
        _mintAndDeposit(composer, 100e18);

        // Disable fast redeem
        vm.prank(owner);
        vault.setFastRedeemEnabled(false);

        vm.prank(composer);
        vm.expectRevert(IStakediTryFastRedeem.FastRedeemDisabled.selector);
        vault.fastWithdrawThroughComposer(50e18, crosschainReceiver, composer);
    }

    function test_fastRedeemThroughComposer_revertsWhenZeroFee() public {
        _mintAndDeposit(composer, 100e18);

        // Try to set zero fee - should revert because MIN_FAST_REDEEM_FEE is 1
        vm.prank(owner);
        vm.expectRevert(IStakediTryFastRedeem.InvalidFastRedeemFee.selector);
        vault.setFastRedeemFee(0);
    }

    function test_fastRedeemThroughComposer_worksWithMinimumShares() public {
        // Deposit larger amount
        _mintAndDeposit(composer, 1000e18);

        // Try to redeem very small amount - should revert because fee rounds to zero
        uint256 minShares = 1;

        vm.prank(composer);
        vm.expectRevert(IStakediTry.InvalidAmount.selector);
        vault.fastRedeemThroughComposer(minShares, crosschainReceiver, composer);
    }

    function test_fastRedeemThroughComposer_worksWithMaximumShares() public {
        uint256 depositAmount = 100e18;
        _mintAndDeposit(composer, depositAmount);

        uint256 allShares = vault.balanceOf(composer);

        vm.prank(composer);
        uint256 returnedAssets = vault.fastRedeemThroughComposer(allShares, crosschainReceiver, composer);

        // Verify all shares were redeemed
        assertEq(vault.balanceOf(composer), 0, "All shares should be redeemed");
        assertGt(returnedAssets, 0, "Should return assets");
    }

    function test_fastWithdrawThroughComposer_worksWithMinimumAssets() public {
        _mintAndDeposit(composer, 1000e18);

        // Try to withdraw very small amount - should revert because fee rounds to zero
        uint256 minAssets = 1;

        vm.prank(composer);
        vm.expectRevert(IStakediTry.InvalidAmount.selector);
        vault.fastWithdrawThroughComposer(minAssets, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_worksWithMaximumAssets() public {
        uint256 depositAmount = 100e18;
        _mintAndDeposit(composer, depositAmount);

        uint256 maxAssets = vault.maxWithdraw(composer);

        vm.prank(composer);
        uint256 returnedShares = vault.fastWithdrawThroughComposer(maxAssets, crosschainReceiver, composer);

        // Verify shares were burned
        assertGt(returnedShares, 0, "Should burn shares");
        assertEq(vault.balanceOf(composer), 0, "All shares should be burned for max withdraw");
    }

    // ============================================================================
    // Phase 4: Precision & Event Verification (4 tests)
    // ============================================================================

    function test_fastRedeemThroughComposer_assetsMatchPreview() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 previewedAssets = vault.previewRedeem(sharesToRedeem);

        uint256 composerAssetsBefore = itryToken.balanceOf(composer);
        uint256 treasuryAssetsBefore = itryToken.balanceOf(treasury);

        vm.prank(composer);
        uint256 returnedAssets = vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);

        // Total assets (composer received + treasury fee) should match preview
        uint256 composerReceived = itryToken.balanceOf(composer) - composerAssetsBefore;
        uint256 treasuryReceived = itryToken.balanceOf(treasury) - treasuryAssetsBefore;
        uint256 totalAssets = composerReceived + treasuryReceived;

        assertEq(totalAssets, previewedAssets, "Total assets should match preview");
        assertEq(returnedAssets, composerReceived, "Returned assets should match composer received");
    }

    function test_fastWithdrawThroughComposer_sharesMatchPreview() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 previewedShares = vault.previewWithdraw(assetsToWithdraw);

        vm.prank(composer);
        uint256 returnedShares = vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);

        assertEq(returnedShares, previewedShares, "Returned shares should match preview");
    }

    function test_fastRedeemThroughComposer_eventHasCorrectParameters() public {
        _mintAndDeposit(composer, 100e18);

        uint256 sharesToRedeem = 50e18;
        uint256 expectedTotalAssets = vault.previewRedeem(sharesToRedeem);
        uint256 expectedFee = (expectedTotalAssets * 1000) / 10000;
        uint256 expectedNetAssets = expectedTotalAssets - expectedFee;

        // Verify all event parameters
        vm.expectEmit(true, true, true, true);
        emit FastRedeemedThroughComposer(
            composer,              // composer (indexed)
            crosschainReceiver,    // crosschainReceiver (indexed)
            composer,              // owner (indexed)
            sharesToRedeem,        // shares
            expectedNetAssets,     // assets (net after fee)
            expectedFee            // feeAssets
        );

        vm.prank(composer);
        vault.fastRedeemThroughComposer(sharesToRedeem, crosschainReceiver, composer);
    }

    function test_fastWithdrawThroughComposer_eventHasCorrectParameters() public {
        _mintAndDeposit(composer, 100e18);

        uint256 assetsToWithdraw = 50e18;
        uint256 expectedShares = vault.previewWithdraw(assetsToWithdraw);
        uint256 expectedFee = (assetsToWithdraw * 1000) / 10000;
        uint256 expectedNetAssets = assetsToWithdraw - expectedFee;

        // Verify all event parameters
        vm.expectEmit(true, true, true, true);
        emit FastRedeemedThroughComposer(
            composer,              // composer (indexed)
            crosschainReceiver,    // crosschainReceiver (indexed)
            composer,              // owner (indexed)
            expectedShares,        // shares
            expectedNetAssets,     // assets (net after fee)
            expectedFee            // feeAssets
        );

        vm.prank(composer);
        vault.fastWithdrawThroughComposer(assetsToWithdraw, crosschainReceiver, composer);
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
