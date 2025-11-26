// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IiTryIssuer
 * @notice Interface for the iTRY Issuer contract that manages the minting and redemption of iTRY tokens
 * @dev This contract acts as the central issuer for iTRY stablecoins, handling collateral management,
 *      yield distribution, and user interactions for minting and redeeming iTRY tokens
 */
interface IiTryIssuer {
    // ============================================
    // Custom Errors
    // ============================================

    /// @notice Thrown when an invalid NAV price is returned from the oracle
    /// @param price The invalid price value
    error InvalidNAVPrice(uint256 price);

    /// @notice Thrown when output amount is below the specified minimum
    /// @param output The actual output amount
    /// @param minimum The minimum required amount
    error OutputBelowMinimum(uint256 output, uint256 minimum);

    /// @notice Thrown when attempting to redeem more iTRY than has been issued
    /// @param requested The amount requested to redeem
    /// @param totalIssued The total amount of iTRY issued
    error AmountExceedsITryIssuance(uint256 requested, uint256 totalIssued);

    /// @notice Thrown when no yield is available to process
    /// @param collateralValue The current collateral value
    /// @param totalIssued The total iTRY issued
    error NoYieldAvailable(uint256 collateralValue, uint256 totalIssued);

    /// @notice Thrown when a fee percentage is higher than the allowed maximum.
    /// @param bps The provided basis points value.
    /// @param maxBps The maximum allowed basis points value.
    error FeeTooHigh(uint256 bps, uint256 maxBps);

    // ============================================
    // Events
    // ============================================

    /**
     * @notice Emitted when iTRY tokens are minted
     * @param user The address receiving the minted iTRY tokens
     * @param dlfAmount The amount of DLF tokens used as collateral (after fees)
     * @param iTryAmount The amount of iTRY tokens minted
     * @param navPrice The NAV price used for the conversion (scaled by 1e18)
     * @param feeInBPS The mint fee applied in basis points
     */
    event ITRYIssued(address indexed user, uint256 dlfAmount, uint256 iTryAmount, uint256 navPrice, uint256 feeInBPS);

    /**
     * @notice Emitted when iTRY tokens are redeemed
     * @param user The address redeeming iTRY tokens
     * @param iTryAmount The amount of iTRY tokens redeemed
     * @param dlfAmount The amount of DLF tokens returned (after fees)
     * @param fromBuffer Whether the redemption was served from the buffer vault or custodian
     * @param feeInBPS The redemption fee applied in basis points
     */
    event ITRYRedeemed(address indexed user, uint256 iTryAmount, uint256 dlfAmount, bool fromBuffer, uint256 feeInBPS);

    /**
     * @notice Emitted when accumulated yield is minted and distributed
     * @param amount The amount of yield iTRY tokens minted
     * @param receiver The address receiving the yield tokens
     * @param totalCollateralValue The total collateral value after NAV price update
     */
    event YieldDistributed(uint256 amount, address indexed receiver, uint256 totalCollateralValue);

    /**
     * @notice Emitted when a fee is processed during mint or redeem operations
     * @param from The address paying the fee
     * @param to The treasury address receiving the fee
     * @param amount The fee amount in DLF tokens
     */
    event FeeProcessed(address indexed from, address indexed to, uint256 amount);

    /**
     * @notice Emitted when a top-up request is made to the vault
     * @param amount The amount requested from the vault
     */
    event VaultTopUpRequested(uint256 amount);

    /**
     * @notice Emitted when a transfer is requested from the custodian
     * @param to The address to receive the transfer
     * @param amount The amount to be transferred
     */
    event CustodianTransferRequested(address indexed to, uint256 amount);

    /**
     * @notice Emitted when the redemption fee is updated
     * @param oldFee The value of the previous fee
     * @param newFee The value of the new fee
     */
    event RedemptionFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when the mint fee is updated
     * @param oldFee The value of the previous fee
     * @param newFee The value of the new fee
     */
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when the oracle address is updated
     * @param oldOracle The address of the previous oracle contract
     * @param newOracle The address of the new oracle contract
     */
    event OracleUpdated(address oldOracle, address newOracle);

    /**
     * @notice Emitted when the custodian address is updated
     * @param oldCustodian The address of the previous custodian
     * @param newCustodian The address of the new custodian
     */
    event CustodianUpdated(address oldCustodian, address newCustodian);

    /**
     * @notice Emitted when the yield receiver address is updated
     * @param oldYieldReceiver The address of the previous yield receiver contract
     * @param newYieldReceiver The address of the new yield receiver contract
     */
    event YieldReceiverUpdated(address oldYieldReceiver, address newYieldReceiver);

    /**
     * @notice Emitted when the treasury address is updated
     * @param oldTreasury The address of the previous treasury
     * @param newTreasury The address of the new treasury
     */
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    /**
     * @notice Emitted when fast access vault needs to be topped up during redemption
     * @param amount The amount of DLF requested from custodian to top up the vault
     */
    event FastAccessVaultTopUpRequested(uint256 amount);

    /**
     * @notice Emitted when excess iTry is removed from circulation without unlicking DLF
     * @param amount The amount of iTry burned
     * @param newTotalIssued the new total issued amount stored in the contract
     */
    event excessITryRemoved(uint256 amount, uint256 newTotalIssued);

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get the total amount of iTRY tokens currently issued
     * @return The total issued iTRY amount
     */
    function getTotalIssuedITry() external view returns (uint256);

    /**
     * @notice Get the total amount of DLF collateral held under custody
     * @return The total DLF under custody (vault + custodian)
     */
    function getCollateralUnderCustody() external view returns (uint256);

    /**
     * @notice Check if a user has the whitelisted user role
     * @param user The address to check
     * @return True if the user is whitelisted, false otherwise
     */
    function isWhitelistedUser(address user) external view returns (bool);

    /**
     * @notice Preview the amount of iTRY tokens that would be minted for a given DLF amount
     * @dev Calculates iTRY amount after deducting mint fees and applying current NAV price
     * @param dlfAmount The amount of DLF tokens to use as collateral
     * @return iTRYAmount The amount of iTRY tokens that would be minted
     */
    function previewMint(uint256 dlfAmount) external view returns (uint256 iTRYAmount);

    /**
     * @notice Preview the amount of DLF tokens that would be returned for redeeming iTRY tokens
     * @dev Calculates DLF amount after deducting redemption fees and applying current NAV price
     * @param iTRYAmount The amount of iTRY tokens to redeem
     * @return dlfAmount The amount of DLF tokens that would be returned
     */
    function previewRedeem(uint256 iTRYAmount) external view returns (uint256 dlfAmount);

    /**
     * @notice Preview the amount of accumulated yield available for distribution
     * @dev Calculates the difference between current collateral value and total issued iTRY
     * @return The amount of yield that can be minted
     */
    function previewAccumulatedYield() external view returns (uint256);

    // ============================================
    // State-Changing Functions
    // ============================================

    /**
     * @notice Mint iTRY tokens by providing DLF collateral
     * @dev Caller must have WHITELISTED_USER_ROLE and approve this contract to spend DLF tokens
     * @param dlfAmount The amount of DLF tokens to use as collateral
     * @param minAmountOut The minimum amount of iTRY tokens expected
     * @return iTRYAmount The amount of iTRY tokens minted
     */
    function mintITRY(uint256 dlfAmount, uint256 minAmountOut) external returns (uint256 iTRYAmount);

    /**
     * @notice Mint iTRY tokens for a recipient by providing DLF collateral
     * @dev Caller must have WHITELISTED_USER_ROLE and approve this contract to spend DLF tokens
     * @param recipient The address to receive the minted iTRY tokens
     * @param dlfAmount The amount of DLF tokens to use as collateral
     * @param minAmountOut The minimum amount of iTRY tokens expected
     * @return iTRYAmount The amount of iTRY tokens minted
     */
    function mintFor(address recipient, uint256 dlfAmount, uint256 minAmountOut) external returns (uint256 iTRYAmount);

    /**
     * @notice Redeem iTRY tokens for DLF collateral
     * @dev Caller must have WHITELISTED_USER_ROLE. Redemption is served from buffer vault if available,
     *      otherwise a transfer request is made to the custodian
     * @param iTRYAmount The amount of iTRY tokens to redeem
     * @param minAmountOut The minimum amount of DLF tokens expected
     * @return fromBuffer True if redemption was served from buffer vault, false if from custodian
     */
    function redeemITRY(uint256 iTRYAmount, uint256 minAmountOut) external returns (bool fromBuffer);

    /**
     * @notice Redeem iTRY tokens on behalf of a recipient for DLF collateral
     * @dev Caller must have WHITELISTED_USER_ROLE and approve this contract to spend their iTRY tokens.
     *      The redeemed DLF will be sent to the recipient address. Redemption is served from buffer vault
     *      if available, otherwise a transfer request is made to the custodian
     * @param recipient The address to receive the DLF collateral
     * @param iTRYAmount The amount of iTRY tokens to redeem
     * @param minAmountOut The minimum amount of DLF tokens expected
     * @return fromBuffer True if redemption was served from buffer vault, false if from custodian
     */
    function redeemFor(address recipient, uint256 iTRYAmount, uint256 minAmountOut) external returns (bool fromBuffer);

    /**
     * @notice Redeem iTRY tokens without withdrawing DLF from custody
     * @dev Caller must be the Admin to call this function.
     * @dev This function works as an additional remediation system for a situation under which there is a NAV decrease
     * @param iTRYAmount The amount of iTRY tokens to burn
     */
    function burnExcessITry(uint256 iTRYAmount) external;

    // ============================================
    // Admin Functions - Integration Management
    // ============================================

    /**
     * @notice Set the address of the oracle contract
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newOracle The address of the new oracle contract
     */
    function setOracle(address newOracle) external;

    /**
     * @notice Set the address of the custodian
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newCustodian The address of the new custodian
     */
    function setCustodian(address newCustodian) external;

    /**
     * @notice Set the address of the yield receiver contract
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newYieldReceiver The address of the new yield receiver contract
     */
    function setYieldReceiver(address newYieldReceiver) external;

    /**
     * @notice Process and distribute accumulated yield
     * @dev Only callable by owner. Mints iTRY tokens equal to accumulated yield and sends to yield processor
     * @return yieldMinted The amount of yield iTRY tokens minted
     */
    function processAccumulatedYield() external returns (uint256 yieldMinted);
}
