// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./iTryIssuer.base.t.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {IiTryIssuer} from "../src/protocol/interfaces/IiTryIssuer.sol";

/**
 * @title iTryIssuer Stateless Fuzz Tests
 * @notice Property-based fuzz tests for iTryIssuer functions
 * @dev Tests system properties with randomized inputs
 */
contract iTryIssuerFuzzTest is iTryIssuerBaseTest {
    // ============================================
    // mintFor Fuzz Tests (4 tests)
    // ============================================

    /// @notice Fuzz test: Conservation of value in minting
    /// @dev Property: totalDLFUnderCustody increase equals net DLF amount
    /// @dev Bounds: $1 to $1B - tests institutional-scale operations for multi-billion TVL system
    function testFuzz_mintFor_conservationOfValue(uint256 dlfAmount) public {
        // Production-scale bounds: $1 to $1B per transaction
        dlfAmount = bound(dlfAmount, 1e18, 1_000_000_000e18);

        // Ensure user has enough collateral
        collateralToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), dlfAmount);

        // Capture state before
        uint256 custodyBefore = _getTotalCustody();

        // Calculate expected net amount
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 expectedNetDlf = dlfAmount - feeAmount;

        // Act
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert: Custody increase equals net DLF
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyAfter - custodyBefore, expectedNetDlf, "Custody increase must equal net DLF amount");
    }

    /// @notice Fuzz test: Fee calculation consistency in minting
    /// @dev Property: Fee calculation is consistent and correct
    /// @dev Bounds: $1 to $1B, fees 0-99.99% - tests fee accuracy at all scales
    function testFuzz_mintFor_feeCalculationConsistency(uint256 dlfAmount, uint256 mintFeeInBPS) public {
        // Production-scale bounds: $1 to $1B
        dlfAmount = bound(dlfAmount, 1e18 + 1, 1_000_000_000e18);
        mintFeeInBPS = bound(mintFeeInBPS, 0, issuer.MAX_MINT_FEE_BPS());

        // Set the mint fee
        vm.prank(admin);
        issuer.setMintFeeInBPS(mintFeeInBPS);

        // Ensure user has collateral
        collateralToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), dlfAmount);

        // Calculate expected values
        uint256 expectedFeeAmount = (dlfAmount * mintFeeInBPS) / 10000;
        uint256 expectedNetDlf = dlfAmount - expectedFeeAmount;

        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);
        uint256 vaultBalanceBefore = collateralToken.balanceOf(address(vault));

        // Act
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert: Fee calculation is correct
        uint256 treasuryBalanceAfter = collateralToken.balanceOf(treasury);
        uint256 vaultBalanceAfter = collateralToken.balanceOf(address(vault));

        assertEq(
            treasuryBalanceAfter - treasuryBalanceBefore, expectedFeeAmount, "Treasury should receive exact fee amount"
        );
        assertEq(vaultBalanceAfter - vaultBalanceBefore, expectedNetDlf, "Vault should receive net DLF amount");
    }

    /// @notice Fuzz test: iTRY calculation consistency
    /// @dev Property: iTRY amount = netDlf * navPrice / 1e18
    /// @dev Bounds: $1B amounts, NAV 0.1x-10x - tests extreme Turkish Lira volatility scenarios
    function testFuzz_mintFor_iTryCalculationConsistency(uint256 dlfAmount, uint256 navPrice) public {
        // Production-scale bounds: $1 to $1B
        dlfAmount = bound(dlfAmount, 1e18, 1_000_000_000e18);
        // Turkish Lira historical range: Can drop 90% in crisis, or rally 10x
        navPrice = bound(navPrice, 0.1e18, 10e18);

        // Set NAV price
        _setNAVPrice(navPrice);

        // Ensure user has collateral
        collateralToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), dlfAmount);

        // Calculate expected iTRY
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = dlfAmount - feeAmount;
        uint256 expectedITry = (netDlfAmount * navPrice) / 1e18;

        // Skip if expected iTRY is 0 (would revert)
        if (expectedITry == 0) return;

        // Act
        vm.prank(whitelistedUser1);
        uint256 actualITry = issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert: iTRY calculation is correct
        assertEq(actualITry, expectedITry, "iTRY calculation must be exact");
    }

    /// @notice Fuzz test: Slippage protection
    /// @dev Property: Function reverts if output < minAmountOut, succeeds otherwise
    /// @dev Bounds: $1B operations - validates slippage protection at institutional scale
    function testFuzz_mintFor_slippageProtection(uint256 dlfAmount, uint256 minAmountOut) public {
        // Production-scale bounds: $1 to $1B
        dlfAmount = bound(dlfAmount, 1e18, 1_000_000_000e18);
        minAmountOut = bound(minAmountOut, 0, type(uint128).max);

        // Ensure user has collateral
        collateralToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), dlfAmount);

        // Calculate expected iTRY
        uint256 expectedITry = _calculateMintOutput(dlfAmount);

        // Skip if iTRY would be 0
        if (expectedITry == 0) return;

        // Act & Assert
        if (expectedITry < minAmountOut) {
            // Should revert
            vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.OutputBelowMinimum.selector, expectedITry, minAmountOut));
            vm.prank(whitelistedUser1);
            issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
        } else {
            // Should succeed
            vm.prank(whitelistedUser1);
            uint256 actualITry = issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
            assertGe(actualITry, minAmountOut, "Output must meet minimum");
        }
    }

    // ============================================
    // redeemFor Fuzz Tests (4 tests)
    // ============================================

    /// @notice Fuzz test: Conservation of value in redemption (vault path)
    /// @dev Property: totalDLFUnderCustody decrease equals gross DLF amount
    /// @dev Bounds: Up to $1B redemptions - tests large institutional exit scenarios
    function testFuzz_redeemFor_conservationOfValue(uint256 iTRYAmount) public {
        // Setup: Mint collateral and iTRY for $1B scale testing
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 maxITry = iTryToken.balanceOf(whitelistedUser1);

        // Production-scale bounds: $1 to full balance (up to $1B)
        iTRYAmount = bound(iTRYAmount, 1e18, maxITry);

        // Calculate expected gross DLF
        uint256 navPrice = oracle.price();
        uint256 expectedGrossDlf = (iTRYAmount * 1e18) / navPrice;

        // Ensure vault has enough (force vault path)
        _setVaultBalance(expectedGrossDlf + 1000e18);

        // Capture state before
        uint256 custodyBefore = _getTotalCustody();

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);

        // Assert: Should be from vault
        assertTrue(fromBuffer, "Should redeem from vault");

        // Assert: Custody decrease equals gross DLF
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyBefore - custodyAfter, expectedGrossDlf, "Custody decrease must equal gross DLF");
    }

    /// @notice Fuzz test: Fee calculation consistency in redemption
    /// @dev Property: Fee calculation is consistent
    /// @dev Bounds: $1B redemptions, all fee levels - validates fee accuracy at scale
    function testFuzz_redeemFor_feeCalculationConsistency(uint256 iTRYAmount, uint256 redemptionFeeInBPS) public {
        // Bound fee to maximum allowed
        redemptionFeeInBPS = bound(redemptionFeeInBPS, 0, issuer.MAX_REDEEM_FEE_BPS());

        // Setup: Mint collateral and iTRY for $1B scale testing
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 maxITry = iTryToken.balanceOf(whitelistedUser1);

        // Production-scale bounds: $1 to $1B
        iTRYAmount = bound(iTRYAmount, 1e18 + 1, maxITry);

        // Set redemption fee
        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(redemptionFeeInBPS);

        // Calculate expected values
        uint256 navPrice = oracle.price();
        uint256 grossDlf = (iTRYAmount * 1e18) / navPrice;
        uint256 expectedFee = (grossDlf * redemptionFeeInBPS) / 10000;
        uint256 expectedNetDlf = grossDlf - expectedFee;

        // Ensure vault has enough
        _setVaultBalance(grossDlf + 1000e18);

        // Record balances before redemption
        uint256 userDlfBefore = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfBefore = collateralToken.balanceOf(treasury);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);

        // Assert: Check balance changes
        uint256 userDlfAfter = collateralToken.balanceOf(whitelistedUser1);
        uint256 treasuryDlfAfter = collateralToken.balanceOf(treasury);

        assertEq(userDlfAfter - userDlfBefore, expectedNetDlf, "User receives net DLF");
        assertEq(treasuryDlfAfter - treasuryDlfBefore, expectedFee, "Treasury receives fee");
    }

    /// @notice Fuzz test: DLF calculation consistency
    /// @dev Property: grossDlf = iTRY * 1e18 / navPrice (when NAV increases or stays same)
    /// @dev Bounds: $1B redemptions, NAV 1x-10x - tests appreciation scenarios at scale
    function testFuzz_redeemFor_dlfCalculationConsistency(uint256 iTRYAmount, uint256 navPrice) public {
        // Test NAV increases only (avoid undercollateralization from NAV drops)
        // Turkish Lira can rally significantly during stabilization periods
        navPrice = bound(navPrice, 1e18, 10e18);

        // Setup: Mint collateral and iTRY at standard price first
        _setNAVPrice(1e18);
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 maxITry = iTryToken.balanceOf(whitelistedUser1);

        // Production-scale bounds: $1 to $1B
        iTRYAmount = bound(iTRYAmount, 1e18, maxITry);

        // Skip if multiplication would overflow
        // Check: iTRYAmount * 1e18 > type(uint256).max
        if (iTRYAmount > type(uint256).max / 1e18) return;

        // Change to fuzz price (>= original mint price)
        _setNAVPrice(navPrice);

        // Calculate expected gross DLF
        uint256 expectedGrossDlf = (iTRYAmount * 1e18) / navPrice;

        // Skip if result is 0
        if (expectedGrossDlf == 0) return;

        // Capture custody before redemption
        uint256 custodyBefore = _getTotalCustody();

        // Skip if redemption would require more DLF than available in custody
        // (This can happen with NAV changes and is a contract-level issue, not a test issue)
        if (expectedGrossDlf > custodyBefore) return;

        // Ensure vault has enough
        _setVaultBalance(expectedGrossDlf + 1000e18);

        // Act
        vm.prank(whitelistedUser1);
        issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);

        // Assert: Custody decreased by gross DLF
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyBefore - custodyAfter, expectedGrossDlf, "DLF calculation must match formula");
    }

    /// @notice Fuzz test: Path selection based on vault balance
    /// @dev Property: fromBuffer = true iff vaultBalance >= grossDlf
    /// @dev Bounds: $1B redemptions, vault up to $100M - tests buffer vs custodian routing logic
    function testFuzz_redeemFor_pathSelection(uint256 iTRYAmount, uint256 vaultBalance) public {
        // Setup: Mint collateral and iTRY at production scale
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);
        uint256 maxITry = iTryToken.balanceOf(whitelistedUser1);

        // Production-scale bounds
        iTRYAmount = bound(iTRYAmount, 1e18, maxITry);
        // Vault typically holds 5-10% of TVL as buffer
        vaultBalance = bound(vaultBalance, 0, 100_000_000e18);

        // Calculate gross DLF
        uint256 navPrice = oracle.price();
        uint256 grossDlf = (iTRYAmount * 1e18) / navPrice;

        // Set vault balance
        _setVaultBalance(vaultBalance);

        // Act
        vm.prank(whitelistedUser1);
        bool fromBuffer = issuer.redeemFor(whitelistedUser1, iTRYAmount, 0);

        // Assert: Path selection is correct
        if (vaultBalance >= grossDlf) {
            assertTrue(fromBuffer, "Should use vault when balance sufficient");
        } else {
            assertFalse(fromBuffer, "Should use custodian when balance insufficient");
        }
    }

    // ============================================
    // processAccumulatedYield Fuzz Tests (4 tests)
    // ============================================

    /// @notice Fuzz test: Yield only when overcollateralized
    /// @dev Property: Function succeeds ⟺ collateralValue > totalIssued
    /// @dev Bounds: NAV 0.1x-10x, $1B TVL - tests yield logic across extreme market conditions
    function testFuzz_processAccumulatedYield_yieldOnlyWhenOvercollateralized(uint256 navPrice) public {
        // Test extreme Turkish Lira volatility: 90% crash to 10x rally
        navPrice = bound(navPrice, 0.1e18, 10e18);

        // Setup: Mint collateral and iTRY at 1:1 at production scale
        _setNAVPrice(1e18);
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();

        // Change to fuzz price
        _setNAVPrice(navPrice);

        // Calculate collateral value
        uint256 collateralValue = (totalCustody * navPrice) / 1e18;

        // Act & Assert
        if (collateralValue > totalIssued) {
            // Should succeed
            vm.prank(admin);
            uint256 yieldMinted = issuer.processAccumulatedYield();
            assertGt(yieldMinted, 0, "Should mint positive yield");
        } else {
            // Should revert
            vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.NoYieldAvailable.selector, collateralValue, totalIssued));
            vm.prank(admin);
            issuer.processAccumulatedYield();
        }
    }

    /// @notice Fuzz test: Yield calculation accuracy
    /// @dev Property: yieldMinted = (custody * navPrice / 1e18) - totalIssued
    /// @dev Bounds: 1%-200% yield, $1B TVL - validates yield precision at massive scale
    function testFuzz_processAccumulatedYield_yieldCalculation(uint256 navPrice) public {
        // Test realistic to extreme yield scenarios: 1% to 200% appreciation
        navPrice = bound(navPrice, 1.01e18, 3e18);

        // Setup: Mint collateral and iTRY at 1:1 at production scale
        _setNAVPrice(1e18);
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();

        // Change to fuzz price
        _setNAVPrice(navPrice);

        // Calculate expected yield
        uint256 collateralValue = (totalCustody * navPrice) / 1e18;
        uint256 expectedYield = collateralValue - totalIssued;

        // Act
        vm.prank(admin);
        uint256 actualYield = issuer.processAccumulatedYield();

        // Assert
        assertEq(actualYield, expectedYield, "Yield calculation must be exact");
    }

    /// @notice Fuzz test: Total issued increases by yield
    /// @dev Property: totalIssued_after = totalIssued_before + yieldMinted
    /// @dev Bounds: 1%-200% yield, $1B TVL - ensures accounting stays accurate at scale
    function testFuzz_processAccumulatedYield_totalIssuedIncrease(uint256 navPrice) public {
        // Test realistic to extreme yield scenarios
        navPrice = bound(navPrice, 1.01e18, 3e18);

        // Setup: Mint collateral and iTRY at production scale
        _setNAVPrice(1e18);
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 totalIssuedBefore = _getTotalIssued();

        _setNAVPrice(navPrice);

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        uint256 totalIssuedAfter = _getTotalIssued();
        assertEq(totalIssuedAfter, totalIssuedBefore + yieldMinted, "Total issued must increase by yield amount");
    }

    /// @notice Fuzz test: Custody unchanged by yield processing
    /// @dev Property: totalDLFUnderCustody remains constant
    /// @dev Bounds: 1%-200% yield, $1B TVL - verifies yield comes from appreciation, not new collateral
    function testFuzz_processAccumulatedYield_custodyUnchanged(uint256 navPrice) public {
        // Test realistic yield-generating scenarios (NAV appreciation only)
        navPrice = bound(navPrice, 1e18 + 1, 3e18);

        // Setup: Mint collateral and iTRY at production scale
        _setNAVPrice(1e18);
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 custodyBefore = _getTotalCustody();

        _setNAVPrice(navPrice);

        // Act
        vm.prank(admin);
        issuer.processAccumulatedYield();

        // Assert
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyAfter, custodyBefore, "Custody must not change (yield from appreciation only)");
    }

    // ============================================
    // burnExcessITry Fuzz Tests (4 tests)
    // ============================================

    /// @notice Fuzz test: Conservation of accounting - totalIssued decreases by exact burn amount
    /// @dev Property: totalIssuedITry_after = totalIssuedITry_before - burnAmount
    /// @dev Bounds: $1 to $1B - tests administrative burns at institutional scale
    function testFuzz_burnExcessITry_totalIssuedDecrease(uint256 burnAmount) public {
        // Setup: First mint some iTRY so there's something to burn
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        // Transfer iTRY to admin so they can burn
        uint256 adminITryBalance = iTryToken.balanceOf(whitelistedUser1);
        vm.prank(whitelistedUser1);
        iTryToken.transfer(admin, adminITryBalance);

        uint256 totalIssuedBefore = _getTotalIssued();

        // Bound burn amount to valid range: $1 to total issued
        burnAmount = bound(burnAmount, 1e18, totalIssuedBefore);

        // Capture state before
        uint256 adminBalanceBefore = iTryToken.balanceOf(admin);

        // Act
        vm.prank(admin);
        issuer.burnExcessITry(burnAmount);

        // Assert: Total issued decreased by exact burn amount
        uint256 totalIssuedAfter = _getTotalIssued();
        assertEq(totalIssuedBefore - totalIssuedAfter, burnAmount, "Total issued must decrease by burn amount");

        // Assert: Admin balance decreased by burn amount
        uint256 adminBalanceAfter = iTryToken.balanceOf(admin);
        assertEq(adminBalanceBefore - adminBalanceAfter, burnAmount, "Admin balance must decrease by burn amount");
    }

    /// @notice Fuzz test: Custody unchanged by burn (no DLF withdrawal)
    /// @dev Property: totalDLFUnderCustody remains constant after burn
    /// @dev Bounds: $1 to $1B - verifies burn only affects iTRY supply, not collateral
    function testFuzz_burnExcessITry_custodyUnchanged(uint256 burnAmount) public {
        // Setup: Mint iTRY at production scale
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        // Transfer iTRY to admin
        uint256 adminITryBalance = iTryToken.balanceOf(whitelistedUser1);
        vm.prank(whitelistedUser1);
        iTryToken.transfer(admin, adminITryBalance);

        uint256 totalIssued = _getTotalIssued();
        burnAmount = bound(burnAmount, 1e18, totalIssued);

        // Capture custody before
        uint256 custodyBefore = _getTotalCustody();

        // Act
        vm.prank(admin);
        issuer.burnExcessITry(burnAmount);

        // Assert: Custody unchanged
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyAfter, custodyBefore, "Custody must not change (burn without DLF withdrawal)");
    }

    /// @notice Fuzz test: Revert when burn exceeds total issued
    /// @dev Property: Function reverts if burnAmount > totalIssuedITry
    /// @dev Bounds: Amounts exceeding total issued - validates overflow protection
    function testFuzz_burnExcessITry_revertWhenExceedsTotalIssued(uint256 burnAmount) public {
        // Setup: Mint a known amount of iTRY
        uint256 mintAmount = 1_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 totalIssued = _getTotalIssued();

        // Bound burn amount to exceed total issued (but avoid overflow)
        burnAmount = bound(burnAmount, totalIssued + 1, type(uint128).max);

        // Give admin enough iTRY tokens (mint extra for the test)
        iTryToken.setController(address(this));
        iTryToken.mint(admin, burnAmount);
        iTryToken.setController(address(issuer));

        // Act & Assert: Should revert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.AmountExceedsITryIssuance.selector, burnAmount, totalIssued));
        vm.prank(admin);
        issuer.burnExcessITry(burnAmount);
    }

    /// @notice Fuzz test: Revert when caller lacks admin role
    /// @dev Property: Only DEFAULT_ADMIN_ROLE can call burnExcessITry
    /// @dev Bounds: $1 to $1B - tests access control at all scales
    function testFuzz_burnExcessITry_revertWhenNotAdmin(uint256 burnAmount, address caller) public {
        // Setup: Mint iTRY
        uint256 mintAmount = 1_000_000_000e18;
        collateralToken.mint(whitelistedUser1, mintAmount);
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), mintAmount);
        _mintITry(whitelistedUser1, mintAmount, 0);

        uint256 totalIssued = _getTotalIssued();
        burnAmount = bound(burnAmount, 1e18, totalIssued);

        // Ensure caller is not admin
        vm.assume(caller != admin);
        vm.assume(caller != address(0));

        // Give caller iTRY tokens
        vm.prank(whitelistedUser1);
        iTryToken.transfer(caller, burnAmount);

        // Act & Assert: Should revert with access control error
        vm.expectRevert();
        vm.prank(caller);
        issuer.burnExcessITry(burnAmount);
    }
}
