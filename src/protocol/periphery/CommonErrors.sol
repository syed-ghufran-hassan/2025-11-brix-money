// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title CommonErrors
 * @notice Shared error definitions used across protocol contracts
 * @dev These errors are reused by multiple contracts to reduce code duplication
 *      and maintain consistency across the protocol
 */
library CommonErrors {
    /// @notice Thrown when a zero address is provided where it's not allowed
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided where it's not allowed
    error ZeroAmount();

    /// @notice Thrown when a token transfer fails
    error TransferFailed();

    /// @notice Thrown when an operation requires more balance than available
    /// @param requested The amount requested
    /// @param available The amount available
    error InsufficientBalance(uint256 requested, uint256 available);
}
