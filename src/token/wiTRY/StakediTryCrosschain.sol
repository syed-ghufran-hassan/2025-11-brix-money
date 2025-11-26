// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StakediTryFastRedeem} from "./StakediTryFastRedeem.sol";
import {UserCooldown} from "./interfaces/IStakediTryCooldown.sol";
import {IStakediTryCrosschain} from "./interfaces/IStakediTryCrosschain.sol";

/**
 * @title StakediTryCrosschain
 * @notice Extends StakediTryFastRedeem with role-gated helpers for trusted composers
 * @dev A composer (e.g. wiTryVaultComposer) can burn its own shares after bridging them in and
 *      assign the resulting cooldown entitlement to an end-user redeemer. This contract
 *      keeps the cooldown accounting in the redeemer slot while still relying on the base
 *      `_withdraw` routine to maintain iTRY system integrity.
 */
contract StakediTryCrosschain is StakediTryFastRedeem, IStakediTryCrosschain {
    /// @notice Role identifier for trusted composers
    bytes32 public constant COMPOSER_ROLE = keccak256("COMPOSER_ROLE");

    /**
     * @notice Initializes the composer-aware staking vault
     * @param _asset iTRY token address
     * @param initialRewarder Initial rewarder contract
     * @param owner Address that receives the default admin role
     * @param _fastRedeemTreasury Treasury address for fast redeem fees
     */
    constructor(IERC20 _asset, address initialRewarder, address owner, address _fastRedeemTreasury)
        StakediTryFastRedeem(_asset, initialRewarder, owner, _fastRedeemTreasury)
    {}

    /**
     * @inheritdoc IStakediTryCrosschain
     * @return assets Amount of underlying assets locked in cooldown for the redeemer
     */
    function cooldownSharesByComposer(uint256 shares, address redeemer)
        external
        onlyRole(COMPOSER_ROLE)
        ensureCooldownOn
        returns (uint256 assets)
    {
        address composer = msg.sender;
        if (redeemer == address(0)) revert InvalidZeroAddress();
        if (shares > maxRedeem(composer)) revert ExcessiveRedeemAmount();

        assets = previewRedeem(shares);
        _startComposerCooldown(composer, redeemer, shares, assets);
    }

    /**
     * @inheritdoc IStakediTryCrosschain
     * @return shares Amount of shares burned from the composer's balance
     */
    function cooldownAssetsByComposer(uint256 assets, address redeemer)
        external
        onlyRole(COMPOSER_ROLE)
        ensureCooldownOn
        returns (uint256 shares)
    {
        address composer = msg.sender;
        if (redeemer == address(0)) revert InvalidZeroAddress();
        if (assets > maxWithdraw(composer)) revert ExcessiveWithdrawAmount();

        shares = previewWithdraw(assets);
        _startComposerCooldown(composer, redeemer, shares, assets);
    }

    /**
     * @inheritdoc IStakediTryCrosschain
     * @notice Unstake through composer after cooldown period
     * @dev Can only be called by composer role
     * @dev Validates cooldown completion before unstaking
     * @dev Calls silo.withdraw() to transfer assets back to composer
     * @param receiver Address that initiated the unstake request
     * @return assets Amount of assets withdrawn
     */
    function unstakeThroughComposer(address receiver)
        external
        onlyRole(COMPOSER_ROLE)
        nonReentrant
        returns (uint256 assets)
    {
        // Validate valid receiver
        if (receiver == address(0)) revert InvalidZeroAddress();

        UserCooldown storage userCooldown = cooldowns[receiver];
        assets = userCooldown.underlyingAmount;

        if (block.timestamp >= userCooldown.cooldownEnd) {
            userCooldown.cooldownEnd = 0;
            userCooldown.underlyingAmount = 0;

            silo.withdraw(msg.sender, assets); // transfer to wiTryVaultComposer for crosschain transfer
        } else {
            revert InvalidCooldown();
        }

        emit UnstakeThroughComposer(msg.sender, receiver, assets);

        return assets;
    }

    /**
     * @inheritdoc IStakediTryCrosschain
     * @notice Fast redeem through composer by specifying shares
     * @dev Burns shares from composer and immediately redeems assets bypassing cooldown with fee
     * @param shares Amount of shares to redeem from composer balance
     * @param crosschainReceiver Address that will receive iTRY on remote chain
     * @param owner Address whose shares are being redeemed (must be composer)
     * @return assets Amount of assets received (after fees)
     */
    function fastRedeemThroughComposer(uint256 shares, address crosschainReceiver, address owner)
        external
        onlyRole(COMPOSER_ROLE)
        ensureCooldownOn
        ensureFastRedeemEnabled
        returns (uint256 assets)
    {
        address composer = msg.sender;
        if (crosschainReceiver == address(0)) revert InvalidZeroAddress();
        if (shares > maxRedeem(composer)) revert ExcessiveRedeemAmount(); // Composer holds the shares on behave of the owner

        uint256 totalAssets = previewRedeem(shares);
        uint256 feeAssets = _redeemWithFee(shares, totalAssets, composer, composer); // Composer receives the assets for further crosschain transfer

        assets = totalAssets - feeAssets;

        emit FastRedeemedThroughComposer(composer, crosschainReceiver, owner, shares, assets, feeAssets);

        return assets;
    }

    /**
     * @inheritdoc IStakediTryCrosschain
     * @notice Fast redeem through composer by specifying assets
     * @dev Converts assets to shares, burns from composer, immediately redeems bypassing cooldown with fee
     * @param assets Amount of assets to redeem
     * @param crosschainReceiver Address that will receive iTRY on remote chain
     * @param owner Address whose shares are being redeemed (must be composer)
     * @return shares Amount of shares burned
     */
    function fastWithdrawThroughComposer(uint256 assets, address crosschainReceiver, address owner)
        external
        onlyRole(COMPOSER_ROLE)
        ensureCooldownOn
        ensureFastRedeemEnabled
        returns (uint256 shares)
    {
        address composer = msg.sender;
        if (crosschainReceiver == address(0)) revert InvalidZeroAddress();
        if (assets > maxWithdraw(composer)) revert ExcessiveWithdrawAmount(); // Composer holds the assets on behave of the owner

        shares = previewWithdraw(assets);
        uint256 feeAssets = _redeemWithFee(shares, assets, composer, composer); // Composer receives the assets for further crosschain transfer

        emit FastRedeemedThroughComposer(composer, crosschainReceiver, owner, shares, assets - feeAssets, feeAssets);

        return shares;
    }

    /**
     * @dev Internal function to initiate cooldown for a redeemer using composer's shares
     * @param composer Address that owns the shares being burned
     * @param redeemer Address that will be able to claim the cooled-down assets
     * @param shares Amount of shares to burn
     * @param assets Amount of assets to place in cooldown
     * @notice Follows Checks-Effects-Interactions pattern: external call to _withdraw occurs first,
     *         then state changes. _withdraw has nonReentrant modifier from base StakediTryV2 for safety.
     */
    function _startComposerCooldown(address composer, address redeemer, uint256 shares, uint256 assets) private {
        uint104 cooldownEnd = uint104(block.timestamp) + cooldownDuration;

        // Interaction: External call to base contract (protected by nonReentrant modifier)
        _withdraw(composer, address(silo), composer, assets, shares);

        // Effects: State changes after external call (following CEI pattern)
        cooldowns[redeemer].cooldownEnd = cooldownEnd;
        cooldowns[redeemer].underlyingAmount += uint152(assets);

        emit ComposerCooldownInitiated(composer, redeemer, shares, assets, cooldownEnd);
    }
}
