// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakediTryV2} from "./StakediTryCooldown.sol";
import {IStakediTryFastRedeem} from "./interfaces/IStakediTryFastRedeem.sol";

/**
 * @title StakediTryFastRedeem
 * @notice Extends StakediTryV2 with fast redemption functionality
 * @dev Allows users to bypass the cooldown period by paying a fee that goes to the treasury.
 *      This provides liquidity to users who need immediate access to their funds while
 *      maintaining the protocol's stability through fee collection.
 */
contract StakediTryFastRedeem is StakediTryV2, IStakediTryFastRedeem {
    using SafeERC20 for IERC20;

    /// @notice Basis points denominator for fee calculations (100% = 10000 basis points)
    uint256 private constant BASIS_POINTS = 10000;

    /// @notice Fast redemption configuration
    address public fastRedeemTreasury;
    uint16 public fastRedeemFeeInBPS;
    bool public fastRedeemEnabled;
    uint16 public constant MIN_FAST_REDEEM_FEE = 1; // 0.01% minimum fee (1 basis point)
    uint16 public constant MAX_FAST_REDEEM_FEE = 2000; // 20% maximum fee

    /// @notice ensure fast redeem is enabled
    modifier ensureFastRedeemEnabled() {
        if (!fastRedeemEnabled) revert FastRedeemDisabled();
        _;
    }

    /**
     * @notice Constructor for StakediTryFastRedeem contract
     * @param _asset The address of the iTry token
     * @param initialRewarder The address of the initial rewarder
     * @param owner The address of the admin role
     * @param _fastRedeemTreasury The address that will receive fast redemption fees
     */
    constructor(IERC20 _asset, address initialRewarder, address owner, address _fastRedeemTreasury)
        StakediTryV2(_asset, initialRewarder, owner)
    {
        if (_fastRedeemTreasury == address(0)) revert InvalidZeroAddress();

        fastRedeemTreasury = _fastRedeemTreasury;
        fastRedeemEnabled = false;
        fastRedeemFeeInBPS = MAX_FAST_REDEEM_FEE; // Start at maximum fee (20%)
    }

    /* ------------- EXTERNAL ------------- */

    /**
     * @inheritdoc IStakediTryFastRedeem
     */
    function fastRedeem(uint256 shares, address receiver, address owner)
        external
        ensureCooldownOn
        ensureFastRedeemEnabled
        returns (uint256 assets)
    {
        if (shares > maxRedeem(owner)) revert ExcessiveRedeemAmount();

        uint256 totalAssets = previewRedeem(shares);
        uint256 feeAssets = _redeemWithFee(shares, totalAssets, receiver, owner);

        emit FastRedeemed(owner, receiver, shares, totalAssets, feeAssets);

        return totalAssets - feeAssets;
    }

    /**
     * @inheritdoc IStakediTryFastRedeem
     */
    function fastWithdraw(uint256 assets, address receiver, address owner)
        external
        ensureCooldownOn
        ensureFastRedeemEnabled
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) revert ExcessiveWithdrawAmount();

        uint256 totalShares = previewWithdraw(assets);
        uint256 feeAssets = _redeemWithFee(totalShares, assets, receiver, owner);

        emit FastRedeemed(owner, receiver, totalShares, assets, feeAssets);

        return totalShares;
    }

    /**
     * @inheritdoc IStakediTryFastRedeem
     */
    function setFastRedeemEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fastRedeemEnabled = enabled;
        emit FastRedeemEnabledUpdated(enabled);
    }

    /**
     * @inheritdoc IStakediTryFastRedeem
     */
    function setFastRedeemFee(uint16 feeInBPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feeInBPS < MIN_FAST_REDEEM_FEE || feeInBPS > MAX_FAST_REDEEM_FEE) {
            revert InvalidFastRedeemFee();
        }

        uint16 previousFee = fastRedeemFeeInBPS;
        fastRedeemFeeInBPS = feeInBPS;
        emit FastRedeemFeeUpdated(previousFee, feeInBPS);
    }

    /**
     * @inheritdoc IStakediTryFastRedeem
     */
    function setFastRedeemTreasury(address treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury == address(0)) revert InvalidZeroAddress();

        address previousTreasury = fastRedeemTreasury;
        fastRedeemTreasury = treasury;
        emit FastRedeemTreasuryUpdated(previousTreasury, treasury);
    }

    /* ------------- INTERNAL ------------- */

    /**
     * @notice Internal helper to perform redemption with fee split
     * @dev Handles the logic of splitting redemption into treasury fee and net user amount.
     *      Follows ERC4626 naming: "redeem" burns shares to withdraw assets.
     *      Reverts if the fee rounds down to zero.
     *      MIN_SHARES validation happens automatically in _withdraw() calls.
     * @param shares Total shares to burn from owner's balance
     * @param assets Total assets being withdrawn (gross amount before fee deduction)
     * @param receiver Address to receive the net assets (after fee is deducted)
     * @param owner Address that owns the shares being burned (must have approved caller if caller != owner)
     * @return feeAssets Amount of assets sent to treasury as fee
     */
    function _redeemWithFee(uint256 shares, uint256 assets, address receiver, address owner)
        internal
        returns (uint256 feeAssets)
    {
        feeAssets = (assets * fastRedeemFeeInBPS) / BASIS_POINTS;

        // Enforce that fast redemption always has a cost
        if (feeAssets == 0) revert InvalidAmount();

        uint256 feeShares = previewWithdraw(feeAssets);
        uint256 netShares = shares - feeShares;
        uint256 netAssets = assets - feeAssets;

        // Withdraw fee portion to treasury
        _withdraw(_msgSender(), fastRedeemTreasury, owner, feeAssets, feeShares);

        // Withdraw net portion to receiver
        _withdraw(_msgSender(), receiver, owner, netAssets, netShares);
    }
}
