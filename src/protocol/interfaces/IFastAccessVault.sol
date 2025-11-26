// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IFastAccessVault
 * @notice Interface for the Fast Access Vault that provides liquidity buffer for quick iTRY redemptions
 * @dev This vault holds a portion of DLF collateral to serve instant redemptions without waiting for
 *      custodian transfers. It automatically rebalances to maintain optimal buffer levels based on
 *      a configurable target percentage of total AUM. Only the authorized issuer contract can
 *      withdraw funds from the vault.
 */
interface IFastAccessVault {
    // ============================================
    // Custom Errors
    // ============================================

    /// @notice Thrown when an unauthorized address attempts to call a restricted function
    /// @param caller The address that attempted the call
    error UnauthorizedCaller(address caller);

    /// @notice Thrown when a percentage value exceeds the maximum allowed
    /// @param percentage The provided percentage
    /// @param maxPercentage The maximum allowed percentage
    error PercentageTooHigh(uint256 percentage, uint256 maxPercentage);

    /// @notice Thrown when buffer doesn't have sufficient balance for an operation
    /// @param requested The amount requested
    /// @param available The amount available
    error InsufficientBufferBalance(uint256 requested, uint256 available);

    /// @notice Thrown when attempting to transfer to an invalid receiver (e.g., self)
    /// @param receiver The invalid receiver address
    error InvalidReceiver(address receiver);

    // ============================================
    // Events
    // ============================================

    /**
     * @notice Emitted when a transfer is processed from the vault
     * @param receiver The address receiving the tokens
     * @param amount The amount of tokens transferred
     * @param remainingBalance The vault balance after the transfer
     */
    event TransferProcessed(address indexed receiver, uint256 amount, uint256 remainingBalance);

    /**
     * @notice Emitted when a top-up request is made to the custodian
     * @param custodian The custodian address receiving the request
     * @param amount The amount requested from custodian
     * @param targetBalance The target balance the vault is trying to achieve
     */
    event TopUpRequestedFromCustodian(address indexed custodian, uint256 amount, uint256 targetBalance);

    /**
     * @notice Emitted when excess funds are transferred back to the custodian
     * @param custodian The custodian address receiving the excess funds
     * @param amount The amount transferred to custodian
     * @param targetBalance The target balance the vault is maintaining
     */
    event ExcessFundsTransferredToCustodian(address indexed custodian, uint256 amount, uint256 targetBalance);

    /**
     * @notice Emitted when the target liquidity buffer percentage is updated
     * @param oldPercentageBPS The previous target percentage in basis points
     * @param newPercentageBPS The new target percentage in basis points
     */
    event TargetBufferPercentageUpdated(uint256 oldPercentageBPS, uint256 newPercentageBPS);

    /**
     * @notice Emitted when the minimum liquidity buffer balance is updated
     * @param oldMinimum The previous minimum balance
     * @param newMinimum The new minimum balance
     */
    event MinimumBufferBalanceUpdated(uint256 oldMinimum, uint256 newMinimum);

    /**
     * @notice Emitted when the custodian address is updated
     * @param oldCustodian The previous custodian address
     * @param newCustodian The new custodian address
     */
    event CustodianUpdated(address indexed oldCustodian, address indexed newCustodian);

    /**
     * @notice Emitted when tokens are rescued from the contract
     * @param token The address of the token rescued (address(0) for ETH)
     * @param to The address receiving the rescued tokens
     * @param amount The amount rescued
     */
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get the current available balance in the vault
     * @dev Returns the vault token balance held by this contract
     * @return The available balance in vault tokens
     */
    function getAvailableBalance() external view returns (uint256);

    /**
     * @notice Get the authorized issuer contract address
     * @return The address of the issuer contract
     */
    function getIssuerContract() external view returns (address);

    /**
     * @notice Get the target buffer percentage
     * @dev Returns the percentage of total AUM that should be held in the buffer
     * @return The target percentage in basis points (e.g., 500 = 5%)
     */
    function getTargetBufferPercentage() external view returns (uint256);

    /**
     * @notice Get the minimum buffer balance
     * @dev This is the floor below which the buffer should not fall regardless of percentage
     * @return The minimum balance in vault tokens
     */
    function getMinimumBufferBalance() external view returns (uint256);

    // ============================================
    // State-Changing Functions - Transfer Operations
    // ============================================

    /**
     * @notice Process a transfer from the vault to a receiver
     * @dev Only callable by the authorized issuer contract
     * @param _receiver The address to receive the tokens
     * @param _amount The amount of tokens to transfer
     */
    function processTransfer(address _receiver, uint256 _amount) external;

    // ============================================
    // State-Changing Functions - Rebalancing
    // ============================================

    /**
     * @notice Rebalance the vault to match target buffer levels
     * @dev Only callable by owner. Requests top-up from custodian if under target,
     *      or transfers excess to custodian if over target
     *
     */
    function rebalanceFunds() external;

    // ============================================
    // Admin Functions - Configuration
    // ============================================

    /**
     * @notice Set the target buffer percentage
     * @dev Only callable by owner. Maximum allowed is 100% (10000 BPS)
     * @param newTargetPercentageBPS The new target percentage in basis points
     */
    function setTargetBufferPercentage(uint256 newTargetPercentageBPS) external;

    /**
     * @notice Set the minimum buffer balance
     * @dev Only callable by owner. This acts as a floor for the buffer
     * @param newMinimumBufferBalance The new minimum balance in vault tokens
     */
    function setMinimumBufferBalance(uint256 newMinimumBufferBalance) external;

    /**
     * @notice Update the custodian address
     * @dev Only callable by owner
     * @param newCustodian The new custodian address
     */
    function setCustodian(address newCustodian) external;
}
