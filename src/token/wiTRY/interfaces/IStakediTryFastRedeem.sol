// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import {IStakediTryCooldown} from "./IStakediTryCooldown.sol";

/**
 * @title IStakediTryFastRedeem
 * @notice Interface for fast redemption functionality
 * @dev Extends IStakediTryCooldown with fast redemption capabilities that allow users to bypass
 *      the cooldown period by paying a fee
 */
interface IStakediTryFastRedeem is IStakediTryCooldown {
    // Events //
    /// @notice Event emitted when fast redeem is enabled/disabled
    event FastRedeemEnabledUpdated(bool enabled);
    /// @notice Event emitted when fast redeem fee is updated
    event FastRedeemFeeUpdated(uint16 previousFee, uint16 newFee);
    /// @notice Event emitted when fast redeem treasury is updated
    event FastRedeemTreasuryUpdated(address previousTreasury, address newTreasury);
    /// @notice Event emitted when a fast redemption occurs
    event FastRedeemed(
        address indexed owner, address indexed receiver, uint256 shares, uint256 assets, uint256 feeAssets
    );

    // Errors //
    /// @notice Error emitted when fast redeem is disabled
    error FastRedeemDisabled();
    /// @notice Error emitted when fast redeem fee exceeds maximum or is below minimum
    error InvalidFastRedeemFee();

    /**
     * @notice Fast redeem shares for immediate withdrawal with a fee
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive the net assets
     * @param owner Address that owns the shares being redeemed
     * @return assets Net assets received by the receiver (after fee)
     */
    function fastRedeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @notice Fast withdraw assets for immediate withdrawal with a fee
     * @param assets Amount of assets to withdraw (gross, before fee)
     * @param receiver Address to receive the net assets
     * @param owner Address that owns the shares being burned
     * @return shares Total shares burned
     */
    function fastWithdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @notice Enable or disable fast redemption feature
     * @param enabled True to enable, false to disable
     */
    function setFastRedeemEnabled(bool enabled) external;

    /**
     * @notice Set the fast redemption fee in basis points
     * @param feeInBPS Fee in basis points (e.g., 500 = 5%)
     */
    function setFastRedeemFee(uint16 feeInBPS) external;

    /**
     * @notice Set the treasury address that receives fast redemption fees
     * @param treasury Address of the treasury
     */
    function setFastRedeemTreasury(address treasury) external;

    /**
     * @notice Get the current fast redemption treasury address
     * @return address Treasury address
     */
    function fastRedeemTreasury() external view returns (address);

    /**
     * @notice Get the current fast redemption fee in basis points
     * @return uint16 Fee in basis points
     */
    function fastRedeemFeeInBPS() external view returns (uint16);

    /**
     * @notice Check if fast redemption is currently enabled
     * @return bool True if enabled
     */
    function fastRedeemEnabled() external view returns (bool);
}
