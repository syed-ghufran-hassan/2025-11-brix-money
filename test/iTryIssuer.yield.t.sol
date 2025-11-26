// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./iTryIssuer.base.t.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {IiTryIssuer} from "../src/protocol/interfaces/IiTryIssuer.sol";

/**
 * @title iTryIssuer processAccumulatedYield Tests
 * @notice Comprehensive unit tests for the processAccumulatedYield function following BTT methodology
 */
contract iTryIssuerYieldTest is iTryIssuerBaseTest {
    // ============================================
    // Access Control Tests (1 test)
    // ============================================

    /// @notice Tests that processAccumulatedYield reverts when caller is not admin
    /// @dev Corresponds to BTT Node 1: Access Control Check
    function test_processAccumulatedYield_whenCallerNotAdmin_reverts() public {
        // Arrange: Set up state with yield available
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18); // 10% appreciation

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.processAccumulatedYield();
    }

    // ============================================
    // Oracle Validation Tests (2 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield reverts when oracle returns zero price
    /// @dev Corresponds to BTT Node 2: Get NAV Price from Oracle
    function test_processAccumulatedYield_whenOracleReturnsZeroPrice_reverts() public {
        // Arrange
        oracle.setPrice(0);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.InvalidNAVPrice.selector, 0));
        vm.prank(admin);
        issuer.processAccumulatedYield();
    }

    /// @notice Tests that processAccumulatedYield proceeds when oracle returns valid price
    /// @dev Corresponds to BTT Node 2: Get NAV Price - success path
    function test_processAccumulatedYield_whenOracleReturnsValidPrice_proceeds() public {
        // Arrange: Set up state with yield available
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18); // 10% appreciation

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        assertGt(yieldMinted, 0, "Should mint positive yield");
    }

    // ============================================
    // Yield Availability Checks Tests (3 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield reverts when system is undercollateralized
    /// @dev Corresponds to BTT Node 4: Check If Yield Available - underwater scenario
    function test_processAccumulatedYield_whenUndercollateralized_reverts() public {
        // Arrange: Create underwater scenario
        // Mint iTRY at normal price
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalIssued = _getTotalIssued();
        uint256 totalCustody = _getTotalCustody();

        // Drop NAV price to make system underwater
        // If custody * newPrice / 1e18 < totalIssued, system is underwater
        // Example: custody = 995e18, issued = 995e18
        // New price = 0.9e18 → collateral value = 895.5e18 < 995e18
        _setNAVPrice(0.9e18);

        uint256 collateralValue = (totalCustody * 0.9e18) / 1e18;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.NoYieldAvailable.selector, collateralValue, totalIssued));
        vm.prank(admin);
        issuer.processAccumulatedYield();
    }

    /// @notice Tests that processAccumulatedYield reverts when at exact parity (no yield)
    /// @dev Corresponds to BTT Node 4: Check If Yield Available - parity scenario
    function test_processAccumulatedYield_whenExactParity_reverts() public {
        // Arrange: Create exact parity scenario
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalIssued = _getTotalIssued();
        uint256 totalCustody = _getTotalCustody();

        // Keep NAV at 1:1 - collateral value equals issued amount
        _setNAVPrice(1e18);

        uint256 collateralValue = (totalCustody * 1e18) / 1e18;

        // Verify we're at parity
        assertEq(collateralValue, totalIssued, "Should be at parity");

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.NoYieldAvailable.selector, collateralValue, totalIssued));
        vm.prank(admin);
        issuer.processAccumulatedYield();
    }

    /// @notice Tests that processAccumulatedYield proceeds when yield is available
    /// @dev Corresponds to BTT Node 4: Check If Yield Available - overcollateralized scenario
    function test_processAccumulatedYield_whenYieldAvailable_proceeds() public {
        // Arrange: Create overcollateralized scenario with yield
        _mintITry(whitelistedUser1, 1000e18, 0);

        // Increase NAV to create yield
        _setNAVPrice(1.1e18); // 10% appreciation

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        assertGt(yieldMinted, 0, "Should mint positive yield");
    }

    // ============================================
    // Calculation Accuracy Tests (2 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield calculates collateral value correctly
    /// @dev Corresponds to BTT Node 3: Calculate Current Collateral Value
    function test_processAccumulatedYield_calculatesCollateralValueCorrectly() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalCustody = _getTotalCustody();

        uint256 newPrice = 1.2e18; // 20% appreciation
        _setNAVPrice(newPrice);

        uint256 expectedCollateralValue = (totalCustody * newPrice) / 1e18;
        uint256 totalIssued = _getTotalIssued();

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert: Yield should equal collateral value minus issued amount
        assertEq(yieldMinted, expectedCollateralValue - totalIssued, "Yield calculation incorrect");
    }

    /// @notice Tests that processAccumulatedYield calculates yield amount correctly
    /// @dev Corresponds to BTT Node 5: Calculate Yield Amount
    function test_processAccumulatedYield_calculatesYieldCorrectly() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssuedBefore = _getTotalIssued();

        uint256 newPrice = 1.15e18; // 15% appreciation
        _setNAVPrice(newPrice);

        uint256 expectedCollateralValue = (totalCustody * newPrice) / 1e18;
        uint256 expectedYield = expectedCollateralValue - totalIssuedBefore;

        // Act
        vm.prank(admin);
        uint256 actualYield = issuer.processAccumulatedYield();

        // Assert
        assertEq(actualYield, expectedYield, "Yield amount should match calculation");
    }

    // ============================================
    // State Changes Tests (3 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield increases totalIssuedITry
    /// @dev Corresponds to BTT Node 6: Mint Yield to yieldReceiver
    function test_processAccumulatedYield_increasesTotalIssuedITry() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalIssuedBefore = _getTotalIssued();

        _setNAVPrice(1.1e18); // 10% appreciation

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        uint256 totalIssuedAfter = _getTotalIssued();
        assertEq(totalIssuedAfter - totalIssuedBefore, yieldMinted, "Total issued should increase by yield amount");
    }

    /// @notice Tests that processAccumulatedYield mints iTRY to yieldReceiver
    /// @dev Corresponds to BTT Node 6: Mint Yield to yieldReceiver
    function test_processAccumulatedYield_mintsITryToYieldReceiver() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);

        uint256 yieldReceiverBalanceBefore = iTryToken.balanceOf(address(yieldProcessor));

        _setNAVPrice(1.1e18); // 10% appreciation

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        uint256 yieldReceiverBalanceAfter = iTryToken.balanceOf(address(yieldProcessor));
        assertEq(
            yieldReceiverBalanceAfter - yieldReceiverBalanceBefore,
            yieldMinted,
            "Yield receiver should receive minted yield"
        );
    }

    /// @notice Tests that processAccumulatedYield does NOT change totalDLFUnderCustody
    /// @dev Corresponds to BTT Node 6: Mint Yield - custody should remain unchanged
    function test_processAccumulatedYield_doesNotChangeTotalDLFUnderCustody() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 custodyBefore = _getTotalCustody();

        _setNAVPrice(1.1e18); // 10% appreciation

        // Act
        vm.prank(admin);
        issuer.processAccumulatedYield();

        // Assert
        uint256 custodyAfter = _getTotalCustody();
        assertEq(custodyAfter, custodyBefore, "Custody should not change (yield is from NAV appreciation)");
    }

    // ============================================
    // External Call Tests (2 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield calls yieldReceiver.processNewYield
    /// @dev Corresponds to BTT Node 7: Notify Yield Receiver
    function test_processAccumulatedYield_callsYieldReceiverProcessNewYield() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18); // 10% appreciation

        _clearYieldCalls();

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        assertEq(yieldProcessor.getYieldCallsCount(), 1, "Should call processNewYield once");
        (uint256 amount,) = yieldProcessor.getYieldCall(0);
        assertEq(amount, yieldMinted, "Should call with correct yield amount");
    }

    /// @notice Tests that processAccumulatedYield reverts when yieldReceiver reverts
    /// @dev Corresponds to BTT Node 7: Notify Yield Receiver - failure scenario
    function test_processAccumulatedYield_whenYieldReceiverReverts_reverts() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18); // 10% appreciation

        // Make yield processor revert
        yieldProcessor.setShouldRevert(true);

        // Act & Assert
        vm.expectRevert("YieldProcessor: revert enabled");
        vm.prank(admin);
        issuer.processAccumulatedYield();
    }

    // ============================================
    // Event Emission Tests (1 test)
    // ============================================

    /// @notice Tests that processAccumulatedYield emits YieldDistributed event
    /// @dev Corresponds to BTT Node 8: Emit YieldDistributed Event
    function test_processAccumulatedYield_emitsYieldDistributedEvent() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();

        uint256 newPrice = 1.1e18;
        _setNAVPrice(newPrice);

        uint256 expectedCollateralValue = (totalCustody * newPrice) / 1e18;
        uint256 expectedYield = expectedCollateralValue - totalIssued;

        // Act & Assert
        vm.expectEmit(false, true, false, true);
        emit YieldDistributed(expectedYield, address(yieldProcessor), expectedCollateralValue);

        vm.prank(admin);
        issuer.processAccumulatedYield();
    }

    // ============================================
    // Integration & Edge Cases Tests (5 tests)
    // ============================================

    /// @notice Tests that processAccumulatedYield succeeds with minimal yield (1 wei)
    /// @dev Edge case: very small yield amount
    function test_processAccumulatedYield_whenMinimalYield_succeeds() public {
        // Arrange: Create scenario with minimal yield
        // This is tricky - need NAV increase to create exactly 1 wei of yield
        // For simplicity, test with small yield > 1 wei

        _mintITry(whitelistedUser1, 1000e18, 0);
        uint256 totalCustody = _getTotalCustody();

        // Calculate price that gives small yield
        // custody * price / 1e18 = issued + 1
        // price = (issued + 1) * 1e18 / custody
        uint256 totalIssued = _getTotalIssued();
        uint256 targetValue = totalIssued + 1e18; // 1 iTRY yield
        uint256 newPrice = (targetValue * 1e18) / totalCustody;

        _setNAVPrice(newPrice);

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        assertGt(yieldMinted, 0, "Should mint positive yield");
        assertLt(yieldMinted, 2e18, "Should mint small yield");
    }

    /// @notice Tests that processAccumulatedYield succeeds with large yield
    /// @dev Edge case: very large yield amount
    function test_processAccumulatedYield_whenLargeYield_succeeds() public {
        // Arrange: Create scenario with large yield
        _mintITry(whitelistedUser1, 1000e18, 0);

        // Double the NAV price for 100% yield
        _setNAVPrice(2e18);

        // Act
        vm.prank(admin);
        uint256 yieldMinted = issuer.processAccumulatedYield();

        // Assert
        assertGt(yieldMinted, 0, "Should mint positive yield");
        // Yield should be approximately equal to total issued (100% appreciation)
        uint256 totalIssued = _getTotalIssued() - yieldMinted; // Subtract just-minted yield
        assertApproxEqRel(yieldMinted, totalIssued, 0.01e18, "Yield should be ~100% of original issued");
    }

    /// @notice Tests that processAccumulatedYield calculates correctly after multiple mints
    /// @dev Integration test: yield calculation after various operations
    function test_processAccumulatedYield_afterMultipleMints_calculatesCorrectYield() public {
        // Arrange: Multiple mints
        _mintITry(whitelistedUser1, 1000e18, 0);
        _mintITry(whitelistedUser2, 500e18, 0);

        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();

        // Increase NAV
        uint256 newPrice = 1.2e18;
        _setNAVPrice(newPrice);

        uint256 expectedCollateralValue = (totalCustody * newPrice) / 1e18;
        uint256 expectedYield = expectedCollateralValue - totalIssued;

        // Act
        vm.prank(admin);
        uint256 actualYield = issuer.processAccumulatedYield();

        // Assert
        assertEq(actualYield, expectedYield, "Yield should be calculated correctly after multiple mints");
    }

    /// @notice Tests that processAccumulatedYield can be called multiple times
    /// @dev Integration test: repeated yield processing
    function test_processAccumulatedYield_canBeCalledMultipleTimes_onlyWhenYieldAvailable() public {
        // Arrange: First yield cycle
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18);

        // Act: Process yield first time
        vm.prank(admin);
        uint256 firstYield = issuer.processAccumulatedYield();
        assertGt(firstYield, 0, "First yield should be positive");

        // Assert: Immediately trying again should fail (no new yield)
        vm.expectRevert(); // NoYieldAvailable
        vm.prank(admin);
        issuer.processAccumulatedYield();

        // Arrange: Increase NAV again to create new yield
        _setNAVPrice(1.2e18);

        // Act: Process yield second time
        vm.prank(admin);
        uint256 secondYield = issuer.processAccumulatedYield();

        // Assert
        assertGt(secondYield, 0, "Second yield should be positive");
    }

    /// @notice Tests that processAccumulatedYield reverts when called twice without NAV change
    /// @dev Verifies that yield can't be double-claimed
    function test_processAccumulatedYield_whenCalledTwiceWithoutNAVChange_revertsSecondTime() public {
        // Arrange
        _mintITry(whitelistedUser1, 1000e18, 0);
        _setNAVPrice(1.1e18);

        // Act: First call succeeds
        vm.prank(admin);
        uint256 firstYield = issuer.processAccumulatedYield();
        assertGt(firstYield, 0, "First yield should be positive");

        // Get current state after first yield processing
        uint256 totalCustody = _getTotalCustody();
        uint256 totalIssued = _getTotalIssued();
        uint256 navPrice = oracle.price();
        uint256 collateralValue = (totalCustody * navPrice) / 1e18;

        // Verify we're back at parity (or close to it)
        assertApproxEqAbs(collateralValue, totalIssued, 1e18, "Should be at or near parity after yield processing");

        // Act & Assert: Second call without NAV change should revert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.NoYieldAvailable.selector, collateralValue, totalIssued));
        vm.prank(admin);
        issuer.processAccumulatedYield();
    }
}
