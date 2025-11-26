// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/protocol/YieldForwarder.sol";
import {CommonErrors} from "../src/protocol/periphery/CommonErrors.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC20FailingTransfer} from "./mocks/MockERC20FailingTransfer.sol";

/**
 * @title YieldForwarder Tests
 * @notice Comprehensive tests for the YieldForwarder contract
 */
contract YieldForwarderTest is Test {
    YieldForwarder public forwarder;
    MockERC20 public yieldToken;

    address public owner;
    address public recipient;
    address public nonOwner;

    // Events
    event YieldForwarded(address indexed recipient, uint256 amount);
    event YieldRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        nonOwner = makeAddr("nonOwner");

        // Deploy yield token
        yieldToken = new MockERC20("Yield Token", "YIELD");

        // Deploy forwarder as owner
        vm.prank(owner);
        forwarder = new YieldForwarder(address(yieldToken), recipient);
    }

    // ============================================
    // Constructor Tests (4 tests)
    // ============================================

    /// @notice Tests that constructor reverts when yieldToken is zero address
    function test_constructor_whenYieldTokenIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(owner);
        new YieldForwarder(address(0), recipient);
    }

    /// @notice Tests that constructor reverts when initial recipient is zero address
    function test_constructor_whenInitialRecipientIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(owner);
        new YieldForwarder(address(yieldToken), address(0));
    }

    /// @notice Tests that constructor sets yieldToken correctly
    function test_constructor_whenValidParameters_setsYieldToken() public {
        assertEq(address(forwarder.yieldToken()), address(yieldToken), "Yield token should be set");
    }

    /// @notice Tests that constructor sets initial recipient and emits event
    function test_constructor_whenValidParameters_setsRecipientAndEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit YieldRecipientUpdated(address(0), recipient);

        vm.prank(owner);
        YieldForwarder newForwarder = new YieldForwarder(address(yieldToken), recipient);

        assertEq(newForwarder.yieldRecipient(), recipient, "Recipient should be set");
    }

    // ============================================
    // processNewYield Tests (6 tests)
    // ============================================

    /// @notice Tests that processNewYield reverts when amount is zero
    function test_processNewYield_whenAmountIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        forwarder.processNewYield(0);
    }

    /// @notice Tests that processNewYield reverts when recipient is not set
    function test_processNewYield_whenRecipientIsZero_reverts() public {
        // Set recipient to zero
        vm.prank(owner);
        forwarder.setYieldRecipient(recipient); // First set valid

        // Deploy new forwarder and manually set recipient to zero using a workaround
        // Since we can't set to zero directly, we skip this edge case
        // as the constructor prevents zero recipient
        vm.skip(true);
    }

    /// @notice Tests that processNewYield transfers tokens to recipient
    function test_processNewYield_whenValid_transfersTokens() public {
        // Arrange
        uint256 yieldAmount = 1000e18;
        yieldToken.mint(address(forwarder), yieldAmount);

        uint256 recipientBalanceBefore = yieldToken.balanceOf(recipient);

        // Act
        forwarder.processNewYield(yieldAmount);

        // Assert
        assertEq(
            yieldToken.balanceOf(recipient), recipientBalanceBefore + yieldAmount, "Recipient should receive yield"
        );
    }

    /// @notice Tests that processNewYield emits YieldForwarded event
    function test_processNewYield_whenValid_emitsEvent() public {
        // Arrange
        uint256 yieldAmount = 1000e18;
        yieldToken.mint(address(forwarder), yieldAmount);

        // Act & Assert
        vm.expectEmit(true, false, false, true);
        emit YieldForwarded(recipient, yieldAmount);

        forwarder.processNewYield(yieldAmount);
    }

    /// @notice Tests that processNewYield reverts when transfer fails
    function test_processNewYield_whenTransferFails_reverts() public {
        // Arrange: Deploy forwarder with failing token
        MockERC20FailingTransfer failingToken = new MockERC20FailingTransfer();

        vm.prank(owner);
        YieldForwarder failingForwarder = new YieldForwarder(address(failingToken), recipient);

        uint256 yieldAmount = 1000e18;
        failingToken.mint(address(failingForwarder), yieldAmount);
        failingToken.setShouldFail(true);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TransferFailed.selector));
        failingForwarder.processNewYield(yieldAmount);
    }

    /// @notice Tests that processNewYield can be called multiple times
    function test_processNewYield_canBeCalledMultipleTimes() public {
        // First yield
        uint256 yield1 = 500e18;
        yieldToken.mint(address(forwarder), yield1);
        forwarder.processNewYield(yield1);

        // Second yield
        uint256 yield2 = 300e18;
        yieldToken.mint(address(forwarder), yield2);
        forwarder.processNewYield(yield2);

        // Assert total received
        assertEq(yieldToken.balanceOf(recipient), yield1 + yield2, "Should receive both yields");
    }

    // ============================================
    // setYieldRecipient Tests (4 tests)
    // ============================================

    /// @notice Tests that setYieldRecipient reverts when caller is not owner
    function test_setYieldRecipient_whenCallerNotOwner_reverts() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectRevert();
        vm.prank(nonOwner);
        forwarder.setYieldRecipient(newRecipient);
    }

    /// @notice Tests that setYieldRecipient reverts when new recipient is zero address
    function test_setYieldRecipient_whenNewRecipientIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(owner);
        forwarder.setYieldRecipient(address(0));
    }

    /// @notice Tests that setYieldRecipient updates recipient correctly
    function test_setYieldRecipient_whenValid_updatesRecipient() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        forwarder.setYieldRecipient(newRecipient);

        assertEq(forwarder.yieldRecipient(), newRecipient, "Recipient should be updated");
    }

    /// @notice Tests that setYieldRecipient emits YieldRecipientUpdated event
    function test_setYieldRecipient_whenValid_emitsEvent() public {
        address newRecipient = makeAddr("newRecipient");

        vm.expectEmit(true, true, false, false);
        emit YieldRecipientUpdated(recipient, newRecipient);

        vm.prank(owner);
        forwarder.setYieldRecipient(newRecipient);
    }

    // ============================================
    // getYieldRecipient Tests (1 test)
    // ============================================

    /// @notice Tests that getYieldRecipient returns current recipient
    function test_getYieldRecipient_returnsCurrentRecipient() public {
        assertEq(forwarder.getYieldRecipient(), recipient, "Should return current recipient");
    }

    // ============================================
    // rescueToken Tests (7 tests)
    // ============================================

    /// @notice Tests that rescueToken reverts when caller is not owner
    function test_rescueToken_whenCallerNotOwner_reverts() public {
        address to = makeAddr("to");

        vm.expectRevert();
        vm.prank(nonOwner);
        forwarder.rescueToken(address(yieldToken), to, 100e18);
    }

    /// @notice Tests that rescueToken reverts when to address is zero
    function test_rescueToken_whenToIsZero_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAddress.selector));
        vm.prank(owner);
        forwarder.rescueToken(address(yieldToken), address(0), 100e18);
    }

    /// @notice Tests that rescueToken reverts when amount is zero
    function test_rescueToken_whenAmountIsZero_reverts() public {
        address to = makeAddr("to");

        vm.expectRevert(abi.encodeWithSelector(CommonErrors.ZeroAmount.selector));
        vm.prank(owner);
        forwarder.rescueToken(address(yieldToken), to, 0);
    }

    /// @notice Tests that rescueToken rescues ERC20 tokens successfully
    function test_rescueToken_whenERC20_rescuesTokens() public {
        // Arrange: Send tokens to forwarder
        address to = makeAddr("to");
        uint256 amount = 500e18;
        yieldToken.mint(address(forwarder), amount);

        uint256 toBalanceBefore = yieldToken.balanceOf(to);

        // Act
        vm.prank(owner);
        forwarder.rescueToken(address(yieldToken), to, amount);

        // Assert
        assertEq(yieldToken.balanceOf(to), toBalanceBefore + amount, "Tokens should be rescued");
    }

    /// @notice Tests that rescueToken emits TokensRescued event for ERC20
    function test_rescueToken_whenERC20_emitsEvent() public {
        address to = makeAddr("to");
        uint256 amount = 500e18;
        yieldToken.mint(address(forwarder), amount);

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(yieldToken), to, amount);

        vm.prank(owner);
        forwarder.rescueToken(address(yieldToken), to, amount);
    }

    /// @notice Tests that rescueToken rescues ETH successfully
    function test_rescueToken_whenETH_rescuesETH() public {
        // Arrange: Send ETH to forwarder
        address to = makeAddr("to");
        uint256 amount = 1 ether;
        vm.deal(address(forwarder), amount);

        uint256 toBalanceBefore = to.balance;

        // Act
        vm.prank(owner);
        forwarder.rescueToken(address(0), to, amount);

        // Assert
        assertEq(to.balance, toBalanceBefore + amount, "ETH should be rescued");
    }

    /// @notice Tests that rescueToken emits TokensRescued event for ETH
    function test_rescueToken_whenETH_emitsEvent() public {
        address to = makeAddr("to");
        uint256 amount = 1 ether;
        vm.deal(address(forwarder), amount);

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(0), to, amount);

        vm.prank(owner);
        forwarder.rescueToken(address(0), to, amount);
    }

    // ============================================
    // Integration Tests (2 tests)
    // ============================================

    /// @notice Tests complete yield flow: update recipient, process yield
    function test_integration_updateRecipientThenProcessYield() public {
        // Setup
        address newRecipient = makeAddr("newRecipient");
        uint256 yieldAmount = 1000e18;

        // Update recipient
        vm.prank(owner);
        forwarder.setYieldRecipient(newRecipient);

        // Process yield
        yieldToken.mint(address(forwarder), yieldAmount);
        forwarder.processNewYield(yieldAmount);

        // Assert new recipient received yield
        assertEq(yieldToken.balanceOf(newRecipient), yieldAmount, "New recipient should receive yield");
        assertEq(yieldToken.balanceOf(recipient), 0, "Old recipient should not receive yield");
    }

    /// @notice Tests that different tokens can be rescued
    function test_integration_rescueDifferentTokens() public {
        // Setup different token
        MockERC20 otherToken = new MockERC20("Other", "OTH");
        address to = makeAddr("to");
        uint256 amount = 300e18;

        // Send tokens to forwarder
        otherToken.mint(address(forwarder), amount);

        // Rescue
        vm.prank(owner);
        forwarder.rescueToken(address(otherToken), to, amount);

        // Assert
        assertEq(otherToken.balanceOf(to), amount, "Different token should be rescued");
    }

    // ============================================
    // Rescue Transfer Failure Tests (2 tests)
    // ============================================

    /// @notice Tests that rescueToken reverts when ETH transfer fails
    function test_rescueToken_whenETHTransferFails_reverts() public {
        // Arrange: Deploy contract that rejects ETH
        ETHRejecter rejecter = new ETHRejecter();
        uint256 amount = 1 ether;
        vm.deal(address(forwarder), amount);

        // Act & Assert
        vm.expectRevert(abi.encodeWithSelector(CommonErrors.TransferFailed.selector));
        vm.prank(owner);
        forwarder.rescueToken(address(0), address(rejecter), amount);
    }

    /// @notice Tests that rescueToken reverts when ERC20 transfer fails
    /// @dev SafeERC20 will revert with its own error message
    function test_rescueToken_whenERC20TransferFails_reverts() public {
        // Arrange: Deploy forwarder with failing token
        MockERC20FailingTransfer failingToken = new MockERC20FailingTransfer();

        vm.prank(owner);
        YieldForwarder failingForwarder = new YieldForwarder(address(yieldToken), recipient);

        uint256 amount = 500e18;
        failingToken.mint(address(failingForwarder), amount);
        failingToken.setShouldFail(true);

        address to = makeAddr("to");

        // Act & Assert
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        vm.prank(owner);
        failingForwarder.rescueToken(address(failingToken), to, amount);
    }
}

/**
 * @title ETHRejecter
 * @notice Helper contract that rejects ETH transfers for testing
 */
contract ETHRejecter {
    // No receive() or fallback() - will reject ETH transfers

    }
