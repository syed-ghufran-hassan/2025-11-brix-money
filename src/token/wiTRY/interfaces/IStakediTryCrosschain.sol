// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IStakediTryCooldown} from "./IStakediTryCooldown.sol";

/**
 * @title IStakediTryCrosschain
 * @notice Interface for StakediTryCrosschain variant that supports composer-managed cooldowns
 * @dev Extends StakediTryCooldown interface with role-gated helpers that allow a trusted
 *      composer (e.g. wiTryVaultComposer) to burn its own shares while crediting cooldown
 *      entitlements to a downstream redeemer that triggered a cross-chain flow.
 */
interface IStakediTryCrosschain is IStakediTryCooldown {
    /**
     * @notice Emitted when a composer starts a cooldown on behalf of a redeemer
     * @param composer Address that burned shares (trusted wiTryVaultComposer)
     * @param redeemer Address that will later call `unstake` on the hub chain
     * @param shares Amount of shares burned from the composer
     * @param assets Amount of assets locked in the silo for the redeemer
     * @param cooldownEnd Timestamp when the redeemer can claim
     */
    event ComposerCooldownInitiated(
        address indexed composer, address indexed redeemer, uint256 shares, uint256 assets, uint104 cooldownEnd
    );

    /**
     * @notice Emitted when unstake is performed through composer
     * @param composer Address that called (wiTryVaultComposer)
     * @param receiver Address that will receive iTRY
     * @param assets Amount of assets unstaked
     */
    event UnstakeThroughComposer(address indexed composer, address indexed receiver, uint256 assets);

    /**
     * @notice Emitted when fast redeem is performed through composer
     * @param composer Address that called (wiTryVaultComposer)
     * @param crosschainReceiver Address that will receive iTRY on remote chain
     * @param owner Address whose shares are being redeemed
     * @param shares Amount of shares redeemed
     * @param assets Amount of assets received (after fees)
     * @param feeAssets Amount of assets paid as fees
     */
    event FastRedeemedThroughComposer(
        address indexed composer,
        address indexed crosschainReceiver,
        address indexed owner,
        uint256 shares,
        uint256 assets,
        uint256 feeAssets
    );

    /**
     * @notice Error thrown when owner parameter doesn't match composer
     */
    error InvalidOwner();

    /**
     * @notice Initiate a cooldown by specifying the number of shares to burn
     * @dev Burns `shares` from the composer and records the resulting assets for the redeemer
     * @param shares Amount of shares to burn from the composer balance
     * @param redeemer Address that will be able to claim the cooled-down assets
     * @return assets Amount of assets that were moved into cooldown
     */
    function cooldownSharesByComposer(uint256 shares, address redeemer) external returns (uint256 assets);

    /**
     * @notice Initiate a cooldown by specifying the amount of assets to lock
     * @dev Converts assets to the corresponding share amount and burns them from the composer
     * @param assets Amount of assets to place into cooldown
     * @param redeemer Address that will be able to claim the cooled-down assets
     * @return shares Amount of shares that were burned
     */
    function cooldownAssetsByComposer(uint256 assets, address redeemer) external returns (uint256 shares);

    /**
     * @notice Returns the composer role identifier
     * @return bytes32 The keccak256 hash of "COMPOSER_ROLE"
     */
    function COMPOSER_ROLE() external view returns (bytes32);

    /**
     * @notice Unstake through composer after cooldown period
     * @dev Can only be called by composer role
     * @dev Validates cooldown completion before unstaking
     * @dev Calls silo.withdraw() to transfer assets back to composer
     *
     * @param receiver Address that initiated the unstake request
     * @return assets Amount of assets withdrawn
     */
    function unstakeThroughComposer(address receiver) external returns (uint256 assets);

    /**
     * @notice Fast redeem through composer by specifying shares
     * @dev Burns shares from composer and immediately redeems assets (bypassing cooldown with fee)
     * @param shares Amount of shares to redeem from composer balance
     * @param crosschainReceiver Address that will receive iTRY on remote chain
     * @param owner Address whose shares are being redeemed
     * @return assets Amount of assets received (after fees)
     */
    function fastRedeemThroughComposer(uint256 shares, address crosschainReceiver, address owner)
        external
        returns (uint256 assets);

    /**
     * @notice Fast redeem through composer by specifying assets
     * @dev Converts assets to shares, burns from composer, immediately redeems (bypassing cooldown with fee)
     * @param assets Amount of assets to redeem
     * @param crosschainReceiver Address that will receive iTRY on remote chain
     * @param owner Address whose shares are being redeemed
     * @return shares Amount of shares burned
     */
    function fastWithdrawThroughComposer(uint256 assets, address crosschainReceiver, address owner)
        external
        returns (uint256 shares);
}
