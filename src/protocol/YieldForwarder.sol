// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldProcessor} from "./periphery/IYieldProcessor.sol";
import {CommonErrors} from "./periphery/CommonErrors.sol";

/**
 * @title YieldForwarder
 * @author Inverter Network
 * @notice A simple yield processor that forwards received yield tokens to a designated recipient address
 * @dev This contract implements the IYieldProcessor interface and acts as a passthrough mechanism
 *      for yield distribution. When yield is processed, it transfers the entire amount to a
 *      pre-configured recipient address.
 *
 *      Key features:
 *      - Owner-controlled recipient address management
 *      - Automatic forwarding of yield tokens upon processing
 *      - Compatible with any ERC20 token
 *      - Event emission for tracking yield forwarding and recipient updates
 *
 * @custom:security-contact security@inverter.network
 */
contract YieldForwarder is IYieldProcessor, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // State Variables
    // ============================================

    /// @notice The ERC20 token that will be forwarded as yield
    IERC20 public immutable yieldToken;

    /// @notice The address that will receive forwarded yield
    address public yieldRecipient;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when yield is forwarded to the recipient
    /// @param recipient The address that received the yield
    /// @param amount The amount of yield tokens forwarded
    event YieldForwarded(address indexed recipient, uint256 amount);

    /// @notice Emitted when the yield recipient address is updated
    /// @param oldRecipient The previous recipient address
    /// @param newRecipient The new recipient address
    event YieldRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Emitted when tokens are rescued by the owner
    /// @param token The address of the token that was rescued
    /// @param to The address that received the rescued tokens
    /// @param amount The amount of tokens rescued
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the YieldForwarder contract
     * @param _yieldToken Address of the ERC20 token to be forwarded as yield
     * @param _initialRecipient Initial address to receive forwarded yield
     */
    constructor(address _yieldToken, address _initialRecipient) {
        if (_yieldToken == address(0)) revert CommonErrors.ZeroAddress();
        if (_initialRecipient == address(0)) revert CommonErrors.ZeroAddress();

        yieldToken = IERC20(_yieldToken);
        yieldRecipient = _initialRecipient;

        emit YieldRecipientUpdated(address(0), _initialRecipient);
    }

    // ============================================
    // External Functions - IYieldProcessor Implementation
    // ============================================

    /**
     * @notice Processes new yield by forwarding it to the designated recipient
     * @dev Implements the IYieldProcessor interface. Transfers the entire yield amount
     *      from this contract to the yieldRecipient address.
     * @param _newYieldAmount The amount of yield tokens to process and forward
     *
     * Requirements:
     * - `_newYieldAmount` must be greater than zero
     * - `yieldRecipient` must not be the zero address
     * - This contract must have sufficient balance of yieldToken
     * - The transfer must succeed
     *
     * Emits a {YieldForwarded} event upon successful transfer
     */
    function processNewYield(uint256 _newYieldAmount) external override {
        if (_newYieldAmount == 0) revert CommonErrors.ZeroAmount();
        if (yieldRecipient == address(0)) revert RecipientNotSet();

        // Transfer yield tokens to the recipient
        if (!yieldToken.transfer(yieldRecipient, _newYieldAmount)) {
            revert CommonErrors.TransferFailed();
        }

        emit YieldForwarded(yieldRecipient, _newYieldAmount);
    }

    // ============================================
    // External Functions - Configuration
    // ============================================

    /**
     * @notice Updates the address that will receive forwarded yield
     * @dev Only callable by the contract owner
     * @param _newRecipient The new address to receive yield
     *
     * Requirements:
     * - Caller must be the contract owner
     * - `_newRecipient` must not be the zero address
     *
     * Emits a {YieldRecipientUpdated} event
     */
    function setYieldRecipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) revert CommonErrors.ZeroAddress();

        address oldRecipient = yieldRecipient;
        yieldRecipient = _newRecipient;

        emit YieldRecipientUpdated(oldRecipient, _newRecipient);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Returns the current yield recipient address
     * @return The address that will receive forwarded yield
     */
    function getYieldRecipient() external view returns (address) {
        return yieldRecipient;
    }

    // ============================================
    // Emergency Functions
    // ============================================
    /*
     * @notice Rescue tokens accidentally sent to this contract
     * @dev Only callable by owner. Can rescue both ERC20 tokens and native ETH
     *      Use address(0) for rescuing ETH
     * @param token The token address to rescue (use address(0) for ETH)
     * @param to The address to send rescued tokens to
     * @param amount The amount to rescue
     */
    function rescueToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert CommonErrors.ZeroAddress();
        if (amount == 0) revert CommonErrors.ZeroAmount();

        if (token == address(0)) {
            // Rescue ETH
            (bool success,) = to.call{value: amount}("");
            if (!success) revert CommonErrors.TransferFailed();
        } else {
            // Rescue ERC20 tokens
            IERC20(token).safeTransfer(to, amount);
        }

        emit TokensRescued(token, to, amount);
    }
}
