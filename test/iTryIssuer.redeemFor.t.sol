// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./iTryIssuer.base.t.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {IiTryIssuer} from "../src/protocol/interfaces/IiTryIssuer.sol";

/**
 * @title iTryIssuer redeemFor Tests
 * @notice Comprehensive unit tests for the redeemFor function following BTT methodology
 */
contract iTryIssuerRedeemForTest is iTryIssuerBaseTest {
    // ============================================
    // Access Control & Input Validation Tests (5 tests)
    // ============================================

    /// @notice Tests that redeemFor reverts when caller is not whitelisted
    /// @dev Corresponds to BTT Node 1: Access Control Check
    function test_redeemFor_whenCallerNotWhitelisted_reverts() public {
        // Arrange
        uint256 iTRYAmount = 100e18;
        uint256 minAmountOut = 0;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.redeemFor(nonWhitelisted, iTRYAmount, minAmountOut);
    }

    /// @notice Tests that redeemFor reverts when recipient is zero address
    /// @dev Corresponds to BTT Node 2: Validate Recipient Address
    function test_redeemFor_whenRecipientIsZeroAddress_reverts() public {
        // Arrange: First mint some iTRY
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYAmount = 100e18;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(address(0), iTRYAmount, 0);
    }

    /// @notice Tests that redeemFor reverts when iTRY amount is zero
    /// @dev Corresponds to BTT Node 3: Validate iTRY Amount
    function test_redeemFor_whenITryAmountIsZero_reverts() public {
        // Arrange
        uint256 iTRYAmount = 0;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);
    }

    /// @notice Tests that redeemFor reverts when amount exceeds total issued
    /// @dev Corresponds to BTT Node 4: Check iTRY Amount vs Total Issued
    function test_redeemFor_whenAmountExceedsTotalIssued_reverts() public {
        // Arrange: Mint some iTRY
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalIssued = _getTotalIssued();
        uint256 iTRYAmount = totalIssued + 1;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.AmountExceedsITryIssuance.selector, iTRYAmount, totalIssued));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);
    }

    /// @notice Tests that redeemFor reverts when oracle returns zero price
    /// @dev Corresponds to BTT Node 5: Get NAV Price from Oracle
    function test_redeemFor_whenOracleReturnsZeroPrice_reverts() public {
        // Arrange: Mint some iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYAmount = 100e18;

        // Set oracle to return 0
        oracle.setPrice(0);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.InvalidNAVPrice.selector, 0));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);
    }

    // ============================================
    // Fee Handling Tests (2 tests)
    // ============================================

    /// @notice Tests that redeemFor works correctly when redemption fee is zero
    /// @dev Corresponds to BTT Node 7: Calculate Redemption Fee - Path A (fee = 0)
    function test_redeemFor_whenRedemptionFeeIsZero_noFeeDeducted() public {
        // Arrange: Set fee to 0
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(0);

        // Mint iTRY first
        uint256 mintAmount = 1000e18;
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        // Calculate expected output with no fee
        uint256 navPrice = oracle.price();
        uint256 expectedGrossDlf = (iTRYBalance * 1e18) / navPrice;

        // Record balances before redemption
        uint256 userDlfBefore = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfBefore = collateralToken.balanceOf(treasury);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert: Check that full gross amount was transferred (no fee to treasury)
        uint256 userDlfAfter = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfAfter = collateralToken.balanceOf(treasury);

        assertEq(userDlfAfter - userDlfBefore, expectedGrossDlf, "User should receive full gross amount");
        assertEq(treasuryDlfAfter - treasuryDlfBefore, 0, "Treasury should receive no fee");
    }

    /// @notice Tests that redeemFor correctly deducts redemption fees
    /// @dev Corresponds to BTT Node 7: Calculate Redemption Fee - Path B (fee > 0)
    function test_redeemFor_whenRedemptionFeeIsSet_feeDeducted() public {
        // Arrange: Mint iTRY first
        uint256 mintAmount = 1000e18;
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        // Calculate expected outputs
        (uint256 expectedNetDlf, uint256 expectedGrossDlf) = _calculateRedeemOutput(iTRYBalance);
        uint256 expectedFee = expectedGrossDlf - expectedNetDlf;

        // Record balances before redemption
        uint256 userDlfBefore = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfBefore = collateralToken.balanceOf(treasury);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert: Check balance changes
        uint256 userDlfAfter = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfAfter = collateralToken.balanceOf(treasury);

        assertEq(userDlfAfter - userDlfBefore, expectedNetDlf, "User should receive net amount");
        assertEq(treasuryDlfAfter - treasuryDlfBefore, expectedFee, "Treasury should receive fee");
    }

    // ============================================
    // Calculation & Slippage Tests (3 tests)
    // ============================================

    /// @notice Tests that redeemFor reverts when calculated gross DLF rounds to zero
    /// @dev Corresponds to BTT Node 8: Validate Gross DLF Amount
    function test_redeemFor_whenCalculatedGrossDlfAmountIsZero_reverts() public {
        // Arrange: Create scenario where gross DLF calculation rounds to 0
        // This requires very small iTRY amount or very high NAV price
        // Set very high NAV price
        _setNAVPrice(type(uint256).max / 1e18); // Very high price

        // Mint with normal price first
        _setNAVPrice(1e18);
        _mintITry(whitelistedUser1, 1000e18, 0);

        // Now set extreme price for redemption
        _setNAVPrice(type(uint256).max / 1e18);

        uint256 iTRYAmount = 1; // 1 wei

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);
    }

    /// @notice Tests that redeemFor reverts when output is below minimum
    /// @dev Corresponds to BTT Node 9: Check Minimum Output (Slippage Protection)
    function test_redeemFor_whenOutputBelowMinimum_reverts() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 expectedNetDlf,) = _calculateRedeemOutput(iTRYBalance);
        uint256 minAmountOut = expectedNetDlf + 1; // Set min higher than expected

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.OutputBelowMinimum.selector, expectedNetDlf, minAmountOut));
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, minAmountOut);
    }

    /// @notice Tests that redeemFor succeeds when output meets minimum
    /// @dev Corresponds to BTT Node 9: Check Minimum Output - success path
    function test_redeemFor_whenOutputMeetsMinimum_succeeds() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 expectedNetDlf,) = _calculateRedeemOutput(iTRYBalance);
        uint256 minAmountOut = expectedNetDlf - 1; // Set min slightly below expected

        // Act
        vm.prank(whitelistedUser1);
        bool result = issuer.redeemFor(whitelistedUser1, iTRYBalance, minAmountOut);

        // Assert
        assertTrue(result, "Should succeed when output meets minimum");
    }

    // ============================================
    // State Changes - Common Tests (2 tests)
    // ============================================

    /// @notice Tests that redeemFor decreases totalIssuedITry correctly
    /// @dev Corresponds to BTT Node 10: Internal Burn
    function test_redeemFor_whenSuccessful_decreasesTotalIssuedITry() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);
        uint256 totalIssuedBefore = _getTotalIssued();

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        uint256 totalIssuedAfter = _getTotalIssued();
        assertEq(
            totalIssuedBefore - totalIssuedAfter, iTRYBalance, "totalIssuedITry should decrease by redeemed amount"
        );
    }

    /// @notice Tests that redeemFor burns iTRY from caller
    /// @dev Corresponds to BTT Node 10: Internal Burn
    function test_redeemFor_whenSuccessful_burnsITryFromCaller() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalanceBefore = iTryToken.balanceOf(whitelistedUser1);
        uint256 redeemAmount = iTRYBalanceBefore / 2; // Redeem half

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, redeemAmount, 0);

        // Assert
        uint256 iTRYBalanceAfter = iTryToken.balanceOf(whitelistedUser1);
        assertEq(iTRYBalanceBefore - iTRYBalanceAfter, redeemAmount, "Caller's iTRY balance should decrease");
    }

    // ============================================
    // Vault Redemption Path Tests (5 tests)
    // ============================================

    /// @notice Tests that redemption uses vault when vault has sufficient balance
    /// @dev Corresponds to BTT Node 11: Check Buffer Vault Balance - Branch A
    function test_redeemFor_whenVaultHasSufficientBalance_redeemsFromVault() public {
        // Arrange: Mint iTRY and ensure vault has sufficient balance
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertTrue(fromBuffer, "Should redeem from vault");
    }

    /// @notice Tests that redemption from vault decreases totalDLFUnderCustody
    /// @dev Corresponds to BTT Sub-Branch 12A-1: Update Accounting
    function test_redeemFor_whenRedeemedFromVault_decreasesTotalDLFUnderCustody() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        uint256 custodyBefore = _getTotalCustody();

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyBefore - custodyAfter, grossDlf, "Custody should decrease by gross amount");
    }

    /// @notice Tests that redemption from vault transfers DLF to recipient
    /// @dev Corresponds to BTT Sub-Branch 12A-2: Transfer Net DLF to Recipient
    function test_redeemFor_whenRedeemedFromVault_transfersDlfToRecipient() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        // Record balance before redemption
        uint256 userDlfBefore = collateralToken.balanceOf(whitelistedUser1);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        uint256 userDlfAfter = collateralToken.balanceOf(whitelistedUser1);
        assertEq(userDlfAfter - userDlfBefore, netDlf, "Should transfer net DLF amount to user");
    }

    /// @notice Tests that redemption from vault transfers fee to treasury
    /// @dev Corresponds to BTT Sub-Branch 12A-3: Transfer Fee to Treasury
    function test_redeemFor_whenRedeemedFromVaultWithFee_transfersFeeToTreasury() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);
        uint256 feeAmount = grossDlf - netDlf;

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        // Record balance before redemption
        uint256 treasuryDlfBefore = collateralToken.balanceOf(treasury);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert: Treasury should receive fee
        uint256 treasuryDlfAfter = collateralToken.balanceOf(treasury);
        assertEq(treasuryDlfAfter - treasuryDlfBefore, feeAmount, "Treasury should receive correct fee amount");
    }

    /// @notice Tests that redemption from vault returns true
    /// @dev Corresponds to BTT Sub-Branch 12A-4: Set Return Value
    function test_redeemFor_whenRedeemedFromVault_returnsTrue() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertTrue(fromBuffer, "Should return true for vault redemption");
    }

    // ============================================
    // Custodian Redemption Path Tests (4 tests)
    // ============================================

    /// @notice Tests that redemption uses custodian when vault has insufficient balance
    /// @dev Corresponds to BTT Node 11: Check Buffer Vault Balance - Branch B
    function test_redeemFor_whenVaultHasInsufficientBalance_redeemsFromCustodian() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Set vault balance to less than needed
        _setVaultBalance(grossDlf - 1);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertFalse(fromBuffer, "Should redeem from custodian");
    }

    /// @notice Tests that custodian redemption emits event for recipient
    /// @dev Corresponds to BTT Sub-Branch 12B-2: Emit Event for Recipient
    function test_redeemFor_whenRedeemedFromCustodian_emitsCustodianTransferRequestedForRecipient() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Set vault balance to insufficient
        _setVaultBalance(0);

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit CustodianTransferRequested(whitelistedUser1, netDlf);

        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);
    }

    /// @notice Tests that custodian redemption emits event for treasury fee
    /// @dev Corresponds to BTT Sub-Branch 12B-1: Emit Event for Fee
    function test_redeemFor_whenRedeemedFromCustodianWithFee_emitsCustodianTransferRequestedForTreasury() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);
        uint256 feeAmount = grossDlf - netDlf;

        // Set vault balance to insufficient
        _setVaultBalance(0);

        // Act & Assert: Should emit 2 events - one for treasury, one for recipient
        vm.expectEmit(true, false, false, true);
        emit CustodianTransferRequested(treasury, feeAmount);

        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);
    }

    /// @notice Tests that custodian redemption returns false
    /// @dev Corresponds to BTT Sub-Branch 12B-3: Set Return Value
    function test_redeemFor_whenRedeemedFromCustodian_returnsFalse() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        // Set vault balance to insufficient
        _setVaultBalance(0);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertFalse(fromBuffer, "Should return false for custodian redemption");
    }

    // ============================================
    // Event Emission Tests (2 tests)
    // ============================================

    /// @notice Tests that redeemFor emits ITRYRedeemed event
    /// @dev Corresponds to BTT Node 13: Emit ITRYRedeemed Event
    function test_redeemFor_whenSuccessful_emitsITRYRedeemedEvent() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);
        uint256 redemptionFee = issuer.redemptionFeeInBPS();

        // Ensure vault has enough for vault path
        _setVaultBalance(grossDlf + 1000e18);

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit ITRYRedeemed(whitelistedUser1, iTRYBalance, netDlf, true, redemptionFee);

        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);
    }

    /// @notice Tests that event has correct fromBuffer value
    /// @dev Verifies event accuracy for both paths
    function test_redeemFor_emitsEventWithCorrectFromBufferValue() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 2000e18, 0);
        uint256 halfBalance = iTryToken.balanceOf(whitelistedUser1) / 2;

        (uint256 netDlf, uint256 grossDlf) = _calculateRedeemOutput(halfBalance);
        uint256 redemptionFee = issuer.redemptionFeeInBPS();

        // Test 1: Vault path
        _setVaultBalance(grossDlf + 1000e18);

        vm.expectEmit(true, false, false, true);
        emit ITRYRedeemed(whitelistedUser1, halfBalance, netDlf, true, redemptionFee);

        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, halfBalance, 0);

        // Test 2: Custodian path
        _setVaultBalance(0);

        // Recalculate for remaining balance
        uint256 remainingBalance = iTryToken.balanceOf(whitelistedUser1);
        (netDlf,) = _calculateRedeemOutput(remainingBalance);

        vm.expectEmit(true, false, false, true);
        emit ITRYRedeemed(whitelistedUser1, remainingBalance, netDlf, false, redemptionFee);

        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, remainingBalance, 0);
    }

    // ============================================
    // Edge Cases Tests (4 tests)
    // ============================================

    /// @notice Tests redeeming the entire issued supply
    /// @dev Edge case where iTRYAmount == totalIssuedITry
    function test_redeemFor_whenAmountEqualsTotalIssued_succeeds() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalIssued = _getTotalIssued();
        uint256 userBalance = iTryToken.balanceOf(whitelistedUser1);

        // Ensure user has all the supply
        assertEq(userBalance, totalIssued, "User should have all supply");

        (, uint256 grossDlf) = _calculateRedeemOutput(totalIssued);
        _setVaultBalance(grossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        bool result = issuer.redeemFor(whitelistedUser1, totalIssued, 0);

        // Assert
        assertTrue(result, "Should succeed");
        assertEq(_getTotalIssued(), 0, "Total issued should be 0");
    }

    /// @notice Tests boundary condition: vault balance exactly equals gross amount
    /// @dev Should use vault path
    function test_redeemFor_whenVaultBalanceExactlyEqualGrossAmount_redeemsFromVault() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Set vault balance to exactly the gross amount needed
        _setVaultBalance(grossDlf);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertTrue(fromBuffer, "Should use vault when balance equals gross amount");
    }

    /// @notice Tests boundary condition: vault balance one wei less than gross amount
    /// @dev Should use custodian path
    function test_redeemFor_whenVaultBalanceOneWeiLessThanGrossAmount_redeemsFromCustodian() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Set vault balance to one wei less than needed
        _setVaultBalance(grossDlf - 1);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertFalse(fromBuffer, "Should use custodian when balance is insufficient");
    }

    /// @notice Tests that redemption works when recipient is the caller
    /// @dev Self-redemption scenario
    function test_redeemFor_whenRecipientIsCaller_succeeds() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);
        _setVaultBalance(grossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        bool result = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertTrue(result, "Should succeed");
        assertEq(iTryToken.balanceOf(whitelistedUser1), 0, "User should have 0 iTRY");
    }

    // ============================================
    // BUG VERIFICATION TEST
    // ============================================

    /// @notice 🚨 CRITICAL BUG TEST: Verifies accounting bug in custodian redemption path
    /// @dev This test DOCUMENTS the bug - totalDLFUnderCustody is NOT updated in custodian path
    /// @dev Expected to FAIL with current implementation
    function test_redeemFor_whenRedeemedFromCustodian_decreasesTotalDLFUnderCustody_BUG() public {
        // Arrange: Mint iTRY first
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 iTRYBalance = iTryToken.balanceOf(whitelistedUser1);

        (, uint256 grossDlf) = _calculateRedeemOutput(iTRYBalance);

        // Set vault balance to 0 to force custodian path
        _setVaultBalance(0);

        uint256 custodyBefore = _getTotalCustody();

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYBalance, 0);

        // Assert
        assertFalse(fromBuffer, "Should use custodian path");

        uint256 custodyAfter = _getTotalCustody();

        // 🚨 THIS ASSERTION WILL FAIL - demonstrating the bug
        // In the current implementation, custodyAfter == custodyBefore (not decremented)
        // It SHOULD decrease by grossDlf
        assertEq(custodyBefore - custodyAfter, grossDlf, "BUG: Custody should decrease but doesn't in custodian path");
    }
}
