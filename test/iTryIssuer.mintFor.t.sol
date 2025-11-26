// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./iTryIssuer.base.t.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {IiTryIssuer} from "../src/protocol/interfaces/IiTryIssuer.sol";
import {MockERC20FailingTransfer} from "./mocks/MockERC20FailingTransfer.sol";

/**
 * @title iTryIssuer mintFor Tests
 * @notice Comprehensive unit tests for the mintFor function following BTT methodology
 */
contract iTryIssuerMintForTest is iTryIssuerBaseTest {
    // ============================================
    // Access Control & Input Validation Tests (6 tests)
    // ============================================

    /// @notice Tests that mintFor reverts when caller is not whitelisted
    /// @dev Corresponds to BTT Node 1: Access Control Check
    function test_mintFor_whenCallerNotWhitelisted_reverts() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 minAmountOut = 0;

        // Act & Assert
        vm.expectRevert(); // AccessControl revert
        vm.prank(nonWhitelisted);
        issuer.mintFor(nonWhitelisted, dlfAmount, minAmountOut);
    }

    /// @notice Tests that mintFor reverts when recipient is zero address
    /// @dev Corresponds to BTT Node 2: Validate Recipient Address
    function test_mintFor_whenRecipientIsZeroAddress_reverts() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 minAmountOut = 0;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(whitelistedUser1);
        issuer.mintFor(address(0), dlfAmount, minAmountOut);
    }

    /// @notice Tests that mintFor reverts when DLF amount is zero
    /// @dev Corresponds to BTT Node 3: Validate DLF Amount
    function test_mintFor_whenDlfAmountIsZero_reverts() public {
        // Arrange
        uint256 dlfAmount = 0;
        uint256 minAmountOut = 0;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
    }

    /// @notice Tests that mintFor reverts when oracle returns zero price
    /// @dev Corresponds to BTT Node 4: Get NAV Price from Oracle
    function test_mintFor_whenOracleReturnsZeroPrice_reverts() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 minAmountOut = 0;
        oracle.setPrice(0); // Set oracle to return 0

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.InvalidNAVPrice.selector, 0));
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
    }

    /// @notice Tests that mintFor reverts when calculated iTRY amount rounds to zero
    /// @dev Corresponds to BTT Node 6: Calculate iTRY Amount - edge case
    function test_mintFor_whenCalculatedITryAmountIsZero_reverts() public {
        // Arrange: Very small amount that will round to zero after fee and conversion

        vm.prank(admin);
        issuer.setMintFeeInBPS(9999);

        uint256 dlfAmount = 1;
        uint256 minAmountOut = 0;

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
    }

    /// @notice Tests that mintFor reverts when output is below minimum required
    /// @dev Corresponds to BTT Node 7: Check Minimum Output (Slippage Protection)
    function test_mintFor_whenOutputBelowMinimum_reverts() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 expectedOutput = _calculateMintOutput(dlfAmount);
        uint256 minAmountOut = expectedOutput + 1; // Set min higher than expected

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(IiTryIssuer.OutputBelowMinimum.selector, expectedOutput, minAmountOut));
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);
    }

    // ============================================
    // Fee Handling Tests (3 tests)
    // ============================================

    /// @notice Tests that mintFor works correctly when mint fee is zero
    /// @dev Corresponds to BTT Node 5: Calculate Mint Fee - Path A (fee = 0)
    function test_mintFor_whenMintFeeIsZero_noFeeDeducted() public {
        // Arrange
        vm.prank(admin);
        issuer.setMintFeeInBPS(0); // Set fee to 0

        uint256 dlfAmount = 1000e18;
        uint256 navPrice = oracle.price();
        uint256 expectedITry = (dlfAmount * navPrice) / 1e18;

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        assertEq(iTryMinted, expectedITry, "iTRY amount should equal full DLF conversion");
        assertEq(collateralToken.balanceOf(treasury), 0, "Treasury should receive no fees");
    }

    /// @notice Tests that mintFor correctly deducts and transfers fees when fee is set
    /// @dev Corresponds to BTT Node 5: Calculate Mint Fee - Path B (fee > 0)
    function test_mintFor_whenMintFeeIsSet_feeDeducted() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = dlfAmount - feeAmount;
        uint256 navPrice = oracle.price();
        uint256 expectedITry = (netDlfAmount * navPrice) / 1e18;

        uint256 treasuryBalanceBefore = collateralToken.balanceOf(treasury);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        assertEq(iTryMinted, expectedITry, "iTRY amount should be net after fee");
        assertEq(collateralToken.balanceOf(treasury), treasuryBalanceBefore + feeAmount, "Treasury should receive fee");
    }

    /// @notice Tests that mintFor reverts when fee transfer fails
    /// @dev Corresponds to BTT Sub-Branch 9C: Transfer Fee to Treasury
    function test_mintFor_whenFeeTransferFails_reverts() public {
        // Arrange: Deploy a new issuer with MockERC20FailingTransfer
        MockERC20FailingTransfer failingToken = new MockERC20FailingTransfer();

        // Deploy new issuer with failing token
        iTryIssuer failingIssuer = new iTryIssuer(
            address(iTryToken),
            address(failingToken),
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

        // Setup: Set controller for iTRY token and whitelist user
        vm.startPrank(admin);
        iTryToken.setController(address(failingIssuer));
        failingIssuer.addToWhitelist(whitelistedUser1);
        failingIssuer.setMintFeeInBPS(100); // 1% fee to trigger fee transfer
        vm.stopPrank();

        // Give user tokens and approve
        uint256 dlfAmount = 1000e18;
        failingToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        failingToken.approve(address(failingIssuer), dlfAmount);

        // Make fee transfer fail
        failingToken.setShouldFail(true);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TransferFailed.selector));
        vm.prank(whitelistedUser1);
        failingIssuer.mintFor(whitelistedUser1, dlfAmount, 0);
    }

    // ============================================
    // State Changes Tests (3 tests)
    // ============================================

    /// @notice Tests that mintFor increases totalIssuedITry correctly
    /// @dev Corresponds to BTT Node 8: Internal Mint
    function test_mintFor_whenSuccessful_increasesTotalIssuedITry() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 expectedITry = _calculateMintOutput(dlfAmount);
        uint256 totalIssuedBefore = _getTotalIssued();

        // Act
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        uint256 totalIssuedAfter = _getTotalIssued();
        assertEq(totalIssuedAfter, totalIssuedBefore + expectedITry, "totalIssuedITry should increase by minted amount");
    }

    /// @notice Tests that mintFor increases totalDLFUnderCustody correctly
    /// @dev Corresponds to BTT Sub-Branch 9A: Update Accounting
    function test_mintFor_whenSuccessful_increasesTotalDLFUnderCustody() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = dlfAmount - feeAmount;
        uint256 totalCustodyBefore = _getTotalCustody();

        // Act
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        uint256 totalCustodyAfter = _getTotalCustody();
        assertEq(
            totalCustodyAfter,
            totalCustodyBefore + netDlfAmount,
            "totalDLFUnderCustody should increase by net DLF amount"
        );
    }

    /// @notice Tests that mintFor mints iTRY tokens to recipient
    /// @dev Corresponds to BTT Node 8: Internal Mint
    function test_mintFor_whenSuccessful_mintsITryToRecipient() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 expectedITry = _calculateMintOutput(dlfAmount);
        uint256 recipientBalanceBefore = iTryToken.balanceOf(whitelistedUser1);

        // Act
        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        uint256 recipientBalanceAfter = iTryToken.balanceOf(whitelistedUser1);
        assertEq(recipientBalanceAfter, recipientBalanceBefore + expectedITry, "Recipient should receive minted iTRY");
    }

    // ============================================
    // Transfer Failures Tests (1 test)
    // ============================================

    /// @notice Tests that mintFor reverts when DLF transfer to vault fails
    /// @dev Corresponds to BTT Sub-Branch 9B: Transfer Net DLF to Vault
    function test_mintFor_whenDlfTransferToVaultFails_reverts() public {
        // Arrange: Deploy a new issuer with MockERC20FailingTransfer
        MockERC20FailingTransfer failingToken = new MockERC20FailingTransfer();

        // Deploy new issuer with failing token
        iTryIssuer failingIssuer = new iTryIssuer(
            address(iTryToken),
            address(failingToken),
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

        // Setup: Set controller for iTRY token and whitelist user
        vm.startPrank(admin);
        iTryToken.setController(address(failingIssuer));
        failingIssuer.addToWhitelist(whitelistedUser1);
        failingIssuer.setMintFeeInBPS(0); // No fee so we test vault transfer, not fee transfer
        vm.stopPrank();

        // Give user tokens and approve
        uint256 dlfAmount = 1000e18;
        failingToken.mint(whitelistedUser1, dlfAmount);
        vm.prank(whitelistedUser1);
        failingToken.approve(address(failingIssuer), dlfAmount);

        // Make DLF transfer to vault fail
        failingToken.setShouldFail(true);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TransferFailed.selector));
        vm.prank(whitelistedUser1);
        failingIssuer.mintFor(whitelistedUser1, dlfAmount, 0);
    }

    // ============================================
    // Event Emission Tests (1 test)
    // ============================================

    /// @notice Tests that mintFor emits ITRYIssued event with correct parameters
    /// @dev Corresponds to BTT Node 10: Emit ITRYIssued Event
    function test_mintFor_whenSuccessful_emitsITRYIssuedEvent() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = dlfAmount - feeAmount;
        uint256 expectedITry = _calculateMintOutput(dlfAmount);
        uint256 navPrice = oracle.price();
        uint256 mintFee = issuer.mintFeeInBPS();

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit ITRYIssued(whitelistedUser1, netDlfAmount, expectedITry, navPrice, mintFee);

        vm.prank(whitelistedUser1);
        issuer.mintFor(whitelistedUser1, dlfAmount, 0);
    }

    // ============================================
    // Success Path Tests (1 test)
    // ============================================

    /// @notice Tests complete happy path for mintFor
    /// @dev Comprehensive test covering all successful branches
    function test_mintFor_whenAllConditionsMet_succeeds() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 expectedITry = _calculateMintOutput(dlfAmount);
        uint256 minAmountOut = expectedITry - 1; // Acceptable slippage

        uint256 totalIssuedBefore = _getTotalIssued();
        uint256 totalCustodyBefore = _getTotalCustody();
        uint256 userBalanceBefore = iTryToken.balanceOf(whitelistedUser1);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);

        // Assert
        assertGe(iTryMinted, minAmountOut, "Output should meet minimum");
        assertEq(iTryMinted, expectedITry, "Output should match calculation");
        assertEq(_getTotalIssued(), totalIssuedBefore + iTryMinted, "Total issued should increase");
        assertGt(_getTotalCustody(), totalCustodyBefore, "Total custody should increase");
        assertEq(iTryToken.balanceOf(whitelistedUser1), userBalanceBefore + iTryMinted, "User balance should increase");
    }

    // ============================================
    // Edge Cases Tests (4 tests)
    // ============================================

    /// @notice Tests that mintFor succeeds when minAmountOut is zero (no slippage protection)
    function test_mintFor_whenMinAmountOutIsZero_succeeds() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 minAmountOut = 0; // No slippage protection

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, minAmountOut);

        // Assert
        assertGt(iTryMinted, 0, "Should mint non-zero amount");
    }

    /// @notice Tests that mintFor handles very large amounts correctly
    function test_mintFor_whenDlfAmountIsVeryLarge_succeeds() public {
        // Arrange
        uint256 dlfAmount = 1_000_000e18; // 1 million DLF

        // Ensure user has enough
        collateralToken.mint(whitelistedUser1, dlfAmount);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        assertGt(iTryMinted, 0, "Should mint non-zero amount");
    }

    /// @notice Tests that mintFor works when recipient is the caller (self-minting)
    function test_mintFor_whenRecipientIsCaller_succeeds() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        uint256 balanceBefore = iTryToken.balanceOf(whitelistedUser1);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(whitelistedUser1, dlfAmount, 0);

        // Assert
        assertEq(
            iTryToken.balanceOf(whitelistedUser1), balanceBefore + iTryMinted, "Caller should receive minted tokens"
        );
    }

    /// @notice Tests that mintFor works when recipient is different from caller
    function test_mintFor_whenRecipientIsDifferent_succeeds() public {
        // Arrange
        uint256 dlfAmount = 1000e18;
        address recipient = whitelistedUser2;
        uint256 recipientBalanceBefore = iTryToken.balanceOf(recipient);

        // Act
        vm.prank(whitelistedUser1);
        uint256 iTryMinted = issuer.mintFor(recipient, dlfAmount, 0);

        // Assert
        assertEq(
            iTryToken.balanceOf(recipient),
            recipientBalanceBefore + iTryMinted,
            "Different recipient should receive minted tokens"
        );
    }
}
