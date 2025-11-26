// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./iTryIssuer.base.t.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {IiTryIssuer} from "../src/protocol/interfaces/IiTryIssuer.sol";

/**
 * @title iTryIssuer Admin, Wrapper, and View Function Tests
 * @notice Tests for constructor validation, admin functions, wrapper functions, and view functions
 */
contract iTryIssuerAdminTest is iTryIssuerBaseTest {
    // ============================================
    // Constructor Validation Tests (4 tests)
    // ============================================

    /// @notice Tests that constructor reverts when _initialAdmin is zero address
    function test_constructor_whenInitialAdminIsZero_reverts() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        new iTryIssuer(
            address(iTryToken),
            address(collateralToken),
            address(oracle),
            treasury,
            address(yieldProcessor),
            custodian,
            address(0), // ❌ Zero admin
            0, // initialIssued
            0, // initialDLFUnderCustody
            500, // vaultTargetPercentageBPS (5%)
            50_000e18 // vaultMinimumBalance
        );
    }

    /// @notice Tests that constructor reverts when _iTryToken is zero address
    function test_constructor_whenITryTokenIsZero_reverts() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        new iTryIssuer(
            address(0), // ❌ Zero iTRY token
            address(collateralToken),
            address(oracle),
            treasury,
            address(yieldProcessor),
            custodian,
            admin,
            0, // initialIssued
            0, // initialDLFUnderCustody
            500, // vaultTargetPercentageBPS (5%)
            50_000e18 // vaultMinimumBalance
        );
    }

    /// @notice Tests that constructor reverts when _collateralToken is zero address
    function test_constructor_whenCollateralTokenIsZero_reverts() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        new iTryIssuer(
            address(iTryToken),
            address(0), // ❌ Zero collateral token
            address(oracle),
            treasury,
            address(yieldProcessor),
            custodian,
            admin,
            0, // initialIssued
            0, // initialDLFUnderCustody
            500, // vaultTargetPercentageBPS (5%)
            50_000e18 // vaultMinimumBalance
        );
    }

    /// @notice Tests that constructor succeeds with valid parameters (happy path)
    function test_constructor_whenValidParameters_succeeds() public {
        // Act
        iTryIssuer newIssuer = new iTryIssuer(
            address(iTryToken),
            address(collateralToken),
            address(oracle),
            treasury,
            address(yieldProcessor),
            custodian,
            admin,
            0, // initialIssued
            0, // initialDLFUnderCustody
            500, // vaultTargetPercentageBPS (5%)
            50_000e18 // vaultMinimumBalance
        );

        // Assert
        assertEq(address(newIssuer.iTryToken()), address(iTryToken), "iTRY token should be set");
        assertEq(address(newIssuer.collateralToken()), address(collateralToken), "Collateral token should be set");
        assertEq(address(newIssuer.oracle()), address(oracle), "Oracle should be set");
        assertEq(newIssuer.treasury(), treasury, "Treasury should be set");
        assertEq(newIssuer.custodian(), custodian, "Custodian should be set");
    }

    // ============================================
    // Wrapper Function Tests - mintITRY (2 tests)
    // ============================================

    /// @notice Tests that mintITRY calls mintFor with msg.sender as recipient
    function test_mintITRY_whenSuccessful_callsMintForWithMsgSender() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 balanceBefore = iTryToken.balanceOf(whitelistedUser1);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTRYAmount = issuer.mintITRY(dlfAmount, 0);

        // Assert
        assertGt(iTRYAmount, 0, "Should mint iTRY");
        assertEq(iTryToken.balanceOf(whitelistedUser1), balanceBefore + iTRYAmount, "Caller should receive iTRY");
    }

    /// @notice Tests that mintITRY reverts when caller is not whitelisted
    function test_mintITRY_whenNotWhitelisted_reverts() public {
        // Arrange
        uint256 dlfAmount = 1000e18;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.mintITRY(dlfAmount, 0);
    }

    // ============================================
    // Wrapper Function Tests - redeemITRY (2 tests)
    // ============================================

    /// @notice Tests that redeemITRY calls redeemFor with msg.sender as recipient
    function test_redeemITRY_whenSuccessful_callsRedeemForWithMsgSender() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);
        _setVaultBalance(grossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemITRY(iTRYBalance, 0);

        // Assert
        assertTrue(fromBuffer, "Should redeem from vault");
        assertEq(iTryToken.balanceOf(whitelistedUser1), 0, "Caller's iTRY should be redeemed");
    }

    /// @notice Tests that redeemITRY reverts when caller is not whitelisted
    function test_redeemITRY_whenNotWhitelisted_reverts() public {
        // Arrange
        uint256 iTRYAmount = 100e18;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.redeemITRY(iTRYAmount, 0);
    }

    // ============================================
    // Admin Function Tests - Fee Management (6 tests)
    // ============================================

    /// @notice Tests that admin can update redemption fee
    function test_setRedemptionFeeInBPS_whenCallerIsAdmin_updatesFee() public {
        // Arrange
        uint256 newFee = 100; // 1%
        uint256 oldFee = issuer.redemptionFeeInBPS();

        // Act
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(newFee);

        // Assert
        assertEq(issuer.redemptionFeeInBPS(), newFee, "Fee should be updated");
        assertNotEq(issuer.redemptionFeeInBPS(), oldFee, "Fee should have changed");
    }

    /// @notice Tests that non-admin cannot update redemption fee
    function test_setRedemptionFeeInBPS_whenCallerNotAdmin_reverts() public {
        // Arrange
        uint256 newFee = 100;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.setRedemptionFeeInBPS(newFee);
    }

    /// @notice Tests that setRedemptionFeeInBPS emits event
    function test_setRedemptionFeeInBPS_emitsRedemptionFeeUpdatedEvent() public {
        // Arrange
        uint256 oldFee = issuer.redemptionFeeInBPS();
        uint256 newFee = 100;

        // Act & Assert
        vm.expectEmit(false, false, false, true);
        emit RedemptionFeeUpdated(oldFee, newFee);

        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(newFee);
    }

    /// @notice Tests that admin can update mint fee
    function test_setMintFeeInBPS_whenCallerIsAdmin_updatesFee() public {
        // Arrange
        uint256 newFee = 100; // 1%
        uint256 oldFee = issuer.mintFeeInBPS();

        // Act
        vm.prank(admin);
        issuer.setMintFeeInBPS(newFee);

        // Assert
        assertEq(issuer.mintFeeInBPS(), newFee, "Fee should be updated");
        assertNotEq(issuer.mintFeeInBPS(), oldFee, "Fee should have changed");
    }

    /// @notice Tests that non-admin cannot update mint fee
    function test_setMintFeeInBPS_whenCallerNotAdmin_reverts() public {
        // Arrange
        uint256 newFee = 100;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.setMintFeeInBPS(newFee);
    }

    /// @notice Tests that setMintFeeInBPS emits event
    function test_setMintFeeInBPS_emitsMintFeeUpdatedEvent() public {
        // Arrange
        uint256 oldFee = issuer.mintFeeInBPS();
        uint256 newFee = 100;

        // Act & Assert
        vm.expectEmit(false, false, false, true);
        emit MintFeeUpdated(oldFee, newFee);

        vm.prank(admin);
        issuer.setMintFeeInBPS(newFee);
    }

    // ============================================
    // Admin Function Tests - Fee Validation (4 tests)
    // ============================================

    /// @notice Tests that setMintFeeInBPS reverts when fee exceeds maximum
    function test_setMintFeeInBPS_whenFeeExceedsMaximum_reverts() public {
        // Arrange
        uint256 invalidFee = issuer.MAX_MINT_FEE_BPS() + 1;

        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(); // FeeTooHigh revert
        issuer.setMintFeeInBPS(invalidFee);
    }

    /// @notice Tests that setMintFeeInBPS succeeds at maximum allowed value
    function test_setMintFeeInBPS_whenFeeAtMaximum_succeeds() public {
        // Arrange
        uint256 maxFee = issuer.MAX_MINT_FEE_BPS(); // MAX_MINT_FEE_BPS

        // Act
        vm.prank(admin);
        issuer.setMintFeeInBPS(maxFee);

        // Assert
        assertEq(issuer.mintFeeInBPS(), maxFee, "Should set to maximum");
    }

    /// @notice Tests that setRedemptionFeeInBPS reverts when fee exceeds maximum
    function test_setRedemptionFeeInBPS_whenFeeExceedsMaximum_reverts() public {
        // Arrange
        uint256 invalidFee = issuer.MAX_REDEEM_FEE_BPS() + 1;

        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(); // FeeTooHigh revert
        issuer.setRedemptionFeeInBPS(invalidFee);
    }

    /// @notice Tests that setRedemptionFeeInBPS succeeds at maximum allowed value
    function test_setRedemptionFeeInBPS_whenFeeAtMaximum_succeeds() public {
        // Arrange
        uint256 maxFee = issuer.MAX_REDEEM_FEE_BPS(); // MAX_REDEEM_FEE_BPS

        // Act
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(maxFee);

        // Assert
        assertEq(issuer.redemptionFeeInBPS(), maxFee, "Should set to maximum");
    }

    // ============================================
    // Admin Function Tests - Whitelist Management (4 tests)
    // ============================================

    /// @notice Tests that whitelist manager can add user to whitelist
    function test_addToWhitelist_whenCallerIsWhitelistManager_addsUser() public {
        // Arrange
        address newUser = makeAddr("newUser");

        // Act
        vm.prank(whitelistManager);
        issuer.addToWhitelist(newUser);

        // Assert: User should now be able to mint
        collateralToken.mint(newUser, 1000e18);
        vm.prank(newUser);
        collateralToken.approve(address(issuer), 1000e18);

        vm.prank(newUser);
        uint256 iTRYAmount = issuer.mintITRY(1000e18, 0);
        assertGt(iTRYAmount, 0, "User should be able to mint");
    }

    /// @notice Tests that non-manager cannot add user to whitelist
    function test_addToWhitelist_whenCallerNotManager_reverts() public {
        // Arrange
        address newUser = makeAddr("newUser");

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.addToWhitelist(newUser);
    }

    /// @notice Tests that whitelist manager can remove user from whitelist
    function test_removeFromWhitelist_whenCallerIsWhitelistManager_removesUser() public {
        // Arrange: User is currently whitelisted
        assertTrue(issuer.hasRole(WHITELISTED_USER_ROLE, whitelistedUser1), "User should be whitelisted");

        // Act
        vm.prank(whitelistManager);
        issuer.removeFromWhitelist(whitelistedUser1);

        // Assert: User should no longer be able to mint
        vm.expectRevert(); // AccessControl revert
        vm.prank(whitelistedUser1);
        issuer.mintITRY(1000e18, 0);
    }

    /// @notice Tests that non-manager cannot remove user from whitelist
    function test_removeFromWhitelist_whenCallerNotManager_reverts() public {
        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.removeFromWhitelist(whitelistedUser1);
    }

    // ============================================
    // View Function Tests - Preview Functions (6 tests)
    // ============================================

    /// @notice Tests that previewMint calculates correct iTRY output
    function test_previewMint_calculatesCorrectITryAmount() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 expectedITry = _calculateMintOutput(dlfAmount);

        // Act
        uint256 previewedITry = issuer.previewMint(dlfAmount);

        // Assert
        assertEq(previewedITry, expectedITry, "Preview should match expected calculation");
    }

    /// @notice Tests that previewMint reverts with zero amount
    function test_previewMint_whenZeroAmount_reverts() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        issuer.previewMint(0);
    }

    /// @notice Tests that previewRedeem calculates correct DLF output
    function test_previewRedeem_calculatesCorrectDlfAmount() public {
        // Arrange
        uint256 iTRYAmount = 1000e18;
        (uint256 expectedDlf,) = _calculateRedeemOutput(iTRYAmount);

        // Act
        uint256 previewedDlf = issuer.previewRedeem(iTRYAmount);

        // Assert
        assertEq(previewedDlf, expectedDlf, "Preview should match expected calculation");
    }

    /// @notice Tests that previewRedeem reverts with zero amount
    function test_previewRedeem_whenZeroAmount_reverts() public {
        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        issuer.previewRedeem(0);
    }

    /// @notice Tests that previewAccumulatedYield calculates correct yield
    function test_previewAccumulatedYield_calculatesCorrectYield() public {
        // Arrange: Set up state with yield available
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();

        uint256 newPrice = 1.1e18;
        _setNAVPrice(newPrice);

        uint256 expectedCollateralValue = (totalCustody * newPrice) / 1e18;
        uint256 expectedYield = expectedCollateralValue - totalIssued;

        // Act
        uint256 previewedYield = issuer.previewAccumulatedYield();

        // Assert
        assertEq(previewedYield, expectedYield, "Preview should match expected yield");
    }

    /// @notice Tests that previewAccumulatedYield returns zero when no yield
    function test_previewAccumulatedYield_whenNoYield_returnsZero() public {
        // Arrange: Set up state at parity (no yield)
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1e18); // Keep at 1:1

        // Act
        uint256 previewedYield = issuer.previewAccumulatedYield();

        // Assert
        assertEq(previewedYield, 0, "Preview should return 0 when no yield");
    }

    /// @notice Tests previewAccumulatedYield when NAV decreases (negative yield)
    function test_previewAccumulatedYield_whenNAVDecreases_returnsZero() public {
        // Arrange: Set up state and decrease NAV
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(0.9e18); // 10% decrease

        // Act
        uint256 previewedYield = issuer.previewAccumulatedYield();

        // Assert
        assertEq(previewedYield, 0, "Should return 0 when collateral value < issued amount");
    }

    /// @notice Tests that previewRedeem calculates correctly with zero fee
    function test_previewRedeem_whenZeroFee_returnsGrossAmount() public {
        // Arrange: Set redemption fee to 0
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(0);

        uint256 iTRYAmount = 1000e18;
        uint256 navPrice = oracle.price();
        uint256 expectedDlf = (iTRYAmount * 1e18) / navPrice;

        // Act
        uint256 previewedDlf = issuer.previewRedeem(iTRYAmount);

        // Assert
        assertEq(previewedDlf, expectedDlf, "Should return gross amount without fee deduction");
    }

    /// @notice Tests that previewMint calculates correctly with zero fee
    function test_previewMint_whenZeroFee_returnsFullAmount() public {
        // Arrange: Set mint fee to 0
        vm.prank(admin);
        issuer.setMintFeeInBPS(0);

        uint256 dlfAmount = 1000e18;
        uint256 navPrice = oracle.price();
        uint256 expectedITry = (dlfAmount * navPrice) / 1e18;

        // Act
        uint256 previewedITry = issuer.previewMint(dlfAmount);

        // Assert
        assertEq(previewedITry, expectedITry, "Should return full amount without fee deduction");
    }

    // ============================================
    // View Function Tests - Getters (2 tests)
    // ============================================

    /// @notice Tests that getTotalIssuedITry returns correct value
    function test_getTotalIssuedITry_returnsCorrectValue() public {
        // Arrange
        uint256 issuedBefore = issuer.getTotalIssuedITry();
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 mintedAmount = iTryToken.balanceOf(whitelistedUser1);

        // Act
        uint256 issuedAfter = issuer.getTotalIssuedITry();

        // Assert
        assertEq(issuedAfter - issuedBefore, mintedAmount, "Total issued should increase by minted amount");
    }

    /// @notice Tests that getCollateralUnderCustody returns correct value
    function test_getCollateralUnderCustody_returnsCorrectValue() public {
        // Arrange
        uint256 custodyBefore = issuer.getCollateralUnderCustody();
        uint256 dlfAmount = 1000e18;
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlf = dlfAmount - feeAmount;

        _mintITry(whitelistedUser1, dlfAmount, 0);

        // Act
        uint256 custodyAfter = issuer.getCollateralUnderCustody();

        // Assert
        assertEq(custodyAfter - custodyBefore, netDlf, "Custody should increase by net DLF amount");
    }

    // ============================================
    // Integration Tests - Fee Impact (2 tests)
    // ============================================

    /// @notice Tests that changing mint fee affects subsequent mints
    function test_feeChange_mintFee_affectsSubsequentMints() public {
        // Arrange: Mint with current fee
        uint256 dlfAmount = 1000e18;
        uint256 iTRYAmount1 = _mintITry(whitelistedUser1, dlfAmount, 0);

        // Change fee
        vm.prank(admin);
        issuer.setMintFeeInBPS(100); // Increase to 1%

        // Act: Mint again with new fee
        collateralToken.mint(whitelistedUser2, dlfAmount);
        vm.prank(whitelistedUser2);
        collateralToken.approve(address(issuer), dlfAmount);

        uint256 iTRYAmount2 = _mintITry(whitelistedUser2, dlfAmount, 0);

        // Assert: Second mint should yield less iTRY due to higher fee
        assertLt(iTRYAmount2, iTRYAmount1, "Higher fee should result in less iTRY minted");
    }

    /// @notice Tests that changing redemption fee affects subsequent redemptions
    function test_feeChange_redemptionFee_affectsSubsequentRedemptions() public {
        // Arrange: Mint iTRY
        _mintITry(whitelistedUser1, 2000e18, 0);
        uint256 halfBalance = iTryToken.balanceOf(whitelistedUser1) / 2;

        // Redeem with current fee
        (, uint256 grossDlf1) = _calculateRedeemOutput(halfBalance);
        _setVaultBalance(grossDlf1 + 1000e18);

        (uint256 netDlf1,) = _calculateRedeemOutput(halfBalance);

        // Change fee
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(100); // Increase to 1%

        // Calculate new expected output
        uint256 newGrossDlf = (halfBalance * 1e18) / oracle.price();
        uint256 newFee = (newGrossDlf * 100) / 10000;
        uint256 newNetDlf = newGrossDlf - newFee;

        _setVaultBalance(newGrossDlf + 1000e18);

        // Act: Preview redemption with new fee
        uint256 previewedDlf = issuer.previewRedeem(halfBalance);

        // Assert: Should get less DLF due to higher fee
        assertLt(previewedDlf, netDlf1, "Higher fee should result in less DLF returned");
        assertEq(previewedDlf, newNetDlf, "Preview should match new fee calculation");
    }

    // ============================================
    // Admin Function Tests - Integration Management (8 tests)
    // ============================================

    /// @notice Tests that admin can update oracle address
    function test_setOracle_whenCallerIsAdmin_updatesOracle() public {
        // Arrange
        address newOracle = makeAddr("newOracle");
        vm.mockCall(newOracle, abi.encodeWithSelector(IOracle.price.selector), abi.encode(1e18));

        // Act
        vm.prank(admin);
        issuer.setOracle(newOracle);

        // Assert
        assertEq(address(issuer.oracle()), newOracle, "Oracle should be updated");
    }

    /// @notice Tests that setOracle reverts with zero address
    function test_setOracle_whenZeroAddress_reverts() public {
        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        issuer.setOracle(address(0));
    }

    /// @notice Tests that admin can update custodian address
    function test_setCustodian_whenCallerIsAdmin_updatesCustodian() public {
        // Arrange
        address newCustodian = makeAddr("newCustodian");

        // Act
        vm.prank(admin);
        issuer.setCustodian(newCustodian);

        // Assert
        assertEq(issuer.custodian(), newCustodian, "Custodian should be updated");
    }

    /// @notice Tests that setCustodian reverts with zero address
    function test_setCustodian_whenZeroAddress_reverts() public {
        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        issuer.setCustodian(address(0));
    }

    /// @notice Tests that admin can update yield receiver address
    function test_setYieldReceiver_whenCallerIsAdmin_updatesYieldReceiver() public {
        // Arrange
        address newYieldReceiver = makeAddr("newYieldReceiver");
        vm.mockCall(newYieldReceiver, abi.encodeWithSelector(IYieldProcessor.processNewYield.selector), abi.encode());

        // Act
        vm.prank(admin);
        issuer.setYieldReceiver(newYieldReceiver);

        // Assert
        assertEq(address(issuer.yieldReceiver()), newYieldReceiver, "YieldReceiver should be updated");
    }

    /// @notice Tests that setYieldReceiver reverts with zero address
    function test_setYieldReceiver_whenZeroAddress_reverts() public {
        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        issuer.setYieldReceiver(address(0));
    }

    /// @notice Tests that admin can update treasury address
    function test_setTreasury_whenCallerIsAdmin_updatesTreasury() public {
        // Arrange
        address newTreasury = makeAddr("newTreasury");

        // Act
        vm.prank(admin);
        issuer.setTreasury(newTreasury);

        // Assert
        assertEq(issuer.treasury(), newTreasury, "Treasury should be updated");
    }

    /// @notice Tests that setTreasury reverts with zero address
    function test_setTreasury_whenZeroAddress_reverts() public {
        // Act & Assert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        issuer.setTreasury(address(0));
    }
}
