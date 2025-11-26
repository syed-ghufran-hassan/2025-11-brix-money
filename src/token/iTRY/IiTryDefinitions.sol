// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.20;

interface IiTryDefinitions {
    enum TransferState {
        FULLY_DISABLED,
        WHITELIST_ENABLED,
        FULLY_ENABLED
    }
    /// @notice This event is fired when the minter is added

    event MinterAdded(address indexed minterAddress);
    /// @notice This event is fired when the minter is removed
    event MinterRemoved(address indexed minterAddress);
    /// @notice Zero address not allowed

    error ZeroAddressException();
    /// @notice Admin can redistribute funds if address is blacklisted

    event LockedAmountRedistributed(address from, address to, uint256 amount);
    /// @notice Admin rescuing tokens sent to contract by accident (supports both ERC20 and ETH)
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    /// @notice Admin can disable or enable token transfers
    event TransferStateUpdated(TransferState prevState, TransferState state);
    /// @notice It's not possible to renounce ownership

    error CantRenounceOwnership();
    /// @notice Only granted roles can perform an action
    error OperationNotAllowed();
    /// @notice Zero amount not allowed
    error ZeroAmount();
    /// @notice Transfer failed
    error TransferFailed();
}
