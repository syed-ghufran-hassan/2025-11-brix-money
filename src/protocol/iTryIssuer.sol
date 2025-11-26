// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SingleAdminAccessControl} from "../utils/SingleAdminAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IiTryIssuer} from "./interfaces/IiTryIssuer.sol";
import {IiTryToken} from "../token/iTRY/interfaces/IiTryToken.sol";
import {IFastAccessVault} from "./interfaces/IFastAccessVault.sol";
import {FastAccessVault} from "./FastAccessVault.sol";
import {IOracle} from "./periphery/IOracle.sol";
import {IYieldProcessor} from "./periphery/IYieldProcessor.sol";
import {CommonErrors} from "./periphery/CommonErrors.sol";

/**
 * @title iTryIssuer
 * @author Inverter Network
 * @notice Central issuer contract for iTRY stablecoins, managing minting, redemption, and yield distribution
 * @dev This contract acts as the controller for iTRY token supply, handling:
 *      - Minting iTRY against DLF collateral
 *      - Redeeming iTRY for DLF (from buffer vault or custodian)
 *      - Processing accumulated yield from NAV appreciation
 *      - Managing fees and whitelisted users
 *      - Coordinating between liquidity vault and custodian for collateral management
 *
 *
 *      The contract uses a role-based access control system with the following roles:
 *      - DEFAULT_ADMIN_ROLE: Can manage all roles and contract parameters
 *      - WHITELIST_MANAGER_ROLE: Can add/remove users from whitelist
 *      - YIELD_DISTRIBUTOR_ROLE: Can process and distribute yield
 *      - INTEGRATION_MANAGER_ROLE: Can set integration contract addresses
 *      - WHITELISTED_USER_ROLE: Can mint and redeem iTRY tokens
 *
 * @custom:security-contact security@inverter.network
 */

contract iTryIssuer is IiTryIssuer, SingleAdminAccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============================================
    // Constants
    // ============================================

    /// @notice Maximum mint fee in basis points (100% = 10000 BPS)
    uint256 public constant MAX_MINT_FEE_BPS = 9999;

    /// @notice Maximum redeem fee in basis points (100% = 10000 BPS)
    uint256 public constant MAX_REDEEM_FEE_BPS = 9999;

    // ============================================
    // State Variables - Dependencies
    // ============================================

    /// @notice The iTRY token contract
    IiTryToken public immutable iTryToken;

    /// @notice The DLF collateral token contract
    IERC20 public immutable collateralToken;

    /// @notice The fast access liquidity vault for quick redemptions
    IFastAccessVault public immutable liquidityVault;

    /// @notice The oracle providing NAV price for DLF/iTRY conversion
    IOracle public oracle;

    /// @notice The custodian address for off-chain collateral management
    address public custodian;

    /// @notice The yield processor contract for distributing accumulated yield
    IYieldProcessor public yieldReceiver;

    // ============================================
    // State Variables - Fee Configuration
    // ============================================

    /// @notice Address receiving protocol fees
    address public treasury;

    /// @notice Mint fee in basis points (1 BPS = 0.01%)
    uint256 public mintFeeInBPS;

    /// @notice Redemption fee in basis points (1 BPS = 0.01%)
    uint256 public redemptionFeeInBPS;

    // ============================================
    // State Variables - Accounting
    // ============================================

    /// @notice Total amount of iTRY tokens currently in circulation
    uint256 private _totalIssuedITry;

    /// @notice Total amount of DLF collateral held under custody (vault + custodian)
    uint256 private _totalDLFUnderCustody;

    // ============================================
    // Access Control Roles
    // ============================================

    /// @notice Role that can manage the whitelist of users
    bytes32 private constant _WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /// @notice Role that can mint new yield and distribute it
    bytes32 private constant _YIELD_DISTRIBUTOR_ROLE = keccak256("YIELD_DISTRIBUTOR_ROLE");

    /// @notice Role that can set the addresses of integration contracts
    bytes32 private constant _INTEGRATION_MANAGER_ROLE = keccak256("INTEGRATION_MANAGER_ROLE");

    /// @notice Role for whitelisted users who can mint and redeem iTRY
    bytes32 private constant _WHITELISTED_USER_ROLE = keccak256("WHITELISTED_USER_ROLE");

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the iTryIssuer contract with all necessary dependencies
     * @param _iTryToken Address of the iTRY token contract
     * @param _collateralToken Address of the DLF collateral token
     * @param _oracle Address of the NAV price oracle
     * @param _treasury Address to receive protocol fees
     * @param _yieldReceiver Address of the yield processor contract
     * @param _custodian Address of the custodian integration
     * @param _initialAdmin Address to receive all initial admin roles
     * @param _initialIssued Initial amount of iTRY already issued (for migration scenarios)
     * @param _initialDLFUnderCustody Initial amount of DLF collateral under custody (for migration scenarios)
     * @param _vaultTargetPercentageBPS Target buffer percentage for FastAccessVault in basis points
     * @param _vaultMinimumBalance Minimum balance for FastAccessVault to maintain
     */
    constructor(
        address _iTryToken,
        address _collateralToken,
        address _oracle,
        address _treasury,
        address _yieldReceiver,
        address _custodian,
        address _initialAdmin,
        uint256 _initialIssued,
        uint256 _initialDLFUnderCustody,
        uint256 _vaultTargetPercentageBPS,
        uint256 _vaultMinimumBalance
    ) {
        if (_initialAdmin == address(0)) revert CommonErrors.ZeroAddress();
        if (_iTryToken == address(0)) revert CommonErrors.ZeroAddress();
        if (_collateralToken == address(0)) revert CommonErrors.ZeroAddress();

        // Deploy FastAccessVault internally with this contract as the issuer
        liquidityVault = IFastAccessVault(
            address(
                new FastAccessVault(
                    _collateralToken,
                    address(this), // Issuer is this contract
                    _custodian,
                    _vaultTargetPercentageBPS,
                    _vaultMinimumBalance,
                    _initialAdmin // Admin for vault ownership
                )
            )
        );

        iTryToken = IiTryToken(_iTryToken);
        collateralToken = IERC20(_collateralToken);
        _setOracle(_oracle);
        _setTreasury(_treasury);
        _setYieldReceiver(_yieldReceiver);
        _setCustodian(_custodian);

        // Set initial fees to 0
        redemptionFeeInBPS = 0;
        mintFeeInBPS = 0;

        // Set initial issued amount and collateral under custody
        _totalIssuedITry = _initialIssued;
        _totalDLFUnderCustody = _initialDLFUnderCustody;

        // Initial role setup - grant all roles to initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(_WHITELIST_MANAGER_ROLE, _initialAdmin);
        _grantRole(_YIELD_DISTRIBUTOR_ROLE, _initialAdmin);
        _grantRole(_INTEGRATION_MANAGER_ROLE, _initialAdmin);

        // Note: The iTRY token admin should call addMinter(address(this)) to grant this contract the MINTER_CONTRACT role
    }

    // ============================================
    // View Functions - Minting Preview
    // ============================================

    /// @inheritdoc IiTryIssuer
    function previewMint(uint256 dlfAmount) external view returns (uint256 iTRYAmount) {
        if (dlfAmount == 0) revert CommonErrors.ZeroAmount();

        uint256 navPrice = oracle.price();
        uint256 netDlfAmount = dlfAmount;

        netDlfAmount = dlfAmount - _calculateMintFee(dlfAmount);

        // Calculate iTRY amount: netDlfAmount * navPrice / 1e18
        iTRYAmount = netDlfAmount * navPrice / 1e18;
    }

    // ============================================
    // View Functions - Redemption Preview
    // ============================================

    /// @inheritdoc IiTryIssuer
    function previewRedeem(uint256 iTRYAmount) external view returns (uint256 dlfAmount) {
        if (iTRYAmount == 0) revert CommonErrors.ZeroAmount();

        uint256 navPrice = oracle.price();

        // Calculate gross DLF amount: iTRYAmount * 1e18 / navPrice
        uint256 grossDlfAmount = iTRYAmount * 1e18 / navPrice;

        // Account for redemption fee if configured
        if (redemptionFeeInBPS > 0) {
            dlfAmount = grossDlfAmount - _calculateRedemptionFee(grossDlfAmount);
        } else {
            dlfAmount = grossDlfAmount;
        }

        return dlfAmount;
    }

    // ============================================
    // View Functions - Yield Preview
    // ============================================

    /// @inheritdoc IiTryIssuer
    function previewAccumulatedYield() external view returns (uint256) {
        uint256 navPrice = oracle.price();

        // Calculate total collateral value: _totalDLFUnderCustody * currentNAVPrice / 1e18
        uint256 currentCollateralValue = _totalDLFUnderCustody * navPrice / 1e18;
        if (currentCollateralValue <= _totalIssuedITry) {
            return 0;
        }
        return currentCollateralValue - _totalIssuedITry;
    }

    // ============================================
    // View Functions - Accounting
    // ============================================

    /// @inheritdoc IiTryIssuer
    function getTotalIssuedITry() external view returns (uint256) {
        return _totalIssuedITry;
    }

    /// @inheritdoc IiTryIssuer
    function getCollateralUnderCustody() external view returns (uint256) {
        return _totalDLFUnderCustody;
    }

    /// @inheritdoc IiTryIssuer
    function isWhitelistedUser(address user) external view returns (bool) {
        return hasRole(_WHITELISTED_USER_ROLE, user);
    }

    // ============================================
    // State-Changing Functions - Minting
    // ============================================

    /// @inheritdoc IiTryIssuer
    function mintITRY(uint256 dlfAmount, uint256 minAmountOut) external returns (uint256 iTRYAmount) {
        return mintFor(msg.sender, dlfAmount, minAmountOut);
    }

    /// @inheritdoc IiTryIssuer
    function mintFor(address recipient, uint256 dlfAmount, uint256 minAmountOut)
        public
        onlyRole(_WHITELISTED_USER_ROLE)
        nonReentrant
        returns (uint256 iTRYAmount)
    {
        // Validate recipient address
        if (recipient == address(0)) revert CommonErrors.ZeroAddress();

        // Validate dlfAmount > 0
        if (dlfAmount == 0) revert CommonErrors.ZeroAmount();

        // Get NAV price from oracle
        uint256 navPrice = oracle.price();
        if (navPrice == 0) revert InvalidNAVPrice(navPrice);

        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = feeAmount > 0 ? (dlfAmount - feeAmount) : dlfAmount;

        // Calculate iTRY amount: netDlfAmount * navPrice / 1e18
        iTRYAmount = netDlfAmount * navPrice / 1e18;

        if (iTRYAmount == 0) revert CommonErrors.ZeroAmount();

        // Check if output meets minimum requirement
        if (iTRYAmount < minAmountOut) {
            revert OutputBelowMinimum(iTRYAmount, minAmountOut);
        }

        // Transfer collateral into vault BEFORE minting (CEI pattern)
        _transferIntoVault(msg.sender, netDlfAmount, feeAmount);

        _mint(recipient, iTRYAmount);

        // Emit event
        emit ITRYIssued(recipient, netDlfAmount, iTRYAmount, navPrice, mintFeeInBPS);
    }

    // ============================================
    // State-Changing Functions - Redemption
    // ============================================

    /// @inheritdoc IiTryIssuer
    function redeemITRY(uint256 iTRYAmount, uint256 minAmountOut) external returns (bool fromBuffer) {
        return redeemFor(msg.sender, iTRYAmount, minAmountOut);
    }

    /// @inheritdoc IiTryIssuer
    function redeemFor(address recipient, uint256 iTRYAmount, uint256 minAmountOut)
        public
        onlyRole(_WHITELISTED_USER_ROLE)
        nonReentrant
        returns (bool fromBuffer)
    {
        // Validate recipient address
        if (recipient == address(0)) revert CommonErrors.ZeroAddress();

        // Validate iTRYAmount > 0
        if (iTRYAmount == 0) revert CommonErrors.ZeroAmount();

        if (iTRYAmount > _totalIssuedITry) {
            revert AmountExceedsITryIssuance(iTRYAmount, _totalIssuedITry);
        }

        // Get NAV price from oracle
        uint256 navPrice = oracle.price();
        if (navPrice == 0) revert InvalidNAVPrice(navPrice);

        // Calculate gross DLF amount: iTRYAmount * 1e18 / navPrice
        uint256 grossDlfAmount = iTRYAmount * 1e18 / navPrice;

        if (grossDlfAmount == 0) revert CommonErrors.ZeroAmount();

        uint256 feeAmount = _calculateRedemptionFee(grossDlfAmount);
        uint256 netDlfAmount = grossDlfAmount - feeAmount;

        // Check if output meets minimum requirement
        if (netDlfAmount < minAmountOut) {
            revert OutputBelowMinimum(netDlfAmount, minAmountOut);
        }

        _burn(msg.sender, iTRYAmount);

        // Check if buffer pool has enough DLF balance
        uint256 bufferBalance = liquidityVault.getAvailableBalance();

        if (bufferBalance >= grossDlfAmount) {
            // Buffer has enough - serve from buffer
            _redeemFromVault(recipient, netDlfAmount, feeAmount);

            fromBuffer = true;
        } else {
            // Buffer insufficient - serve from custodian
            _redeemFromCustodian(recipient, netDlfAmount, feeAmount);

            fromBuffer = false;
        }

        // Emit redemption event
        emit ITRYRedeemed(recipient, iTRYAmount, netDlfAmount, fromBuffer, redemptionFeeInBPS);
    }

 /// @inheritdoc IiTryIssuer
    function burnExcessITry(uint256 iTRYAmount)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        // Validate iTRYAmount > 0
        if (iTRYAmount == 0) revert CommonErrors.ZeroAmount();

        if (iTRYAmount > _totalIssuedITry) {
            revert AmountExceedsITryIssuance(iTRYAmount, _totalIssuedITry);
        }

        _burn(msg.sender, iTRYAmount);


        // Emit redemption event
        emit excessITryRemoved(iTRYAmount, _totalIssuedITry);
    }


    // ============================================
    // State-Changing Functions - Yield Management
    // ============================================

    /// @inheritdoc IiTryIssuer
    function processAccumulatedYield() external onlyRole(_YIELD_DISTRIBUTOR_ROLE) returns (uint256 newYield) {
        // Get current NAV price
        uint256 navPrice = oracle.price();
        if (navPrice == 0) revert InvalidNAVPrice(navPrice);

        // Calculate total collateral value: totalDLFUnderCustody * currentNAVPrice / 1e18
        uint256 currentCollateralValue = _totalDLFUnderCustody * navPrice / 1e18;

        // Calculate yield: currentCollateralValue - _totalIssuedITry
        if (currentCollateralValue <= _totalIssuedITry) {
            revert NoYieldAvailable(currentCollateralValue, _totalIssuedITry);
        }
        newYield = currentCollateralValue - _totalIssuedITry;

        // Mint yield amount to yieldReceiver contract
        _mint(address(yieldReceiver), newYield);

        // Notify yield distributor of received yield
        yieldReceiver.processNewYield(newYield);

        // Emit event
        emit YieldDistributed(newYield, address(yieldReceiver), currentCollateralValue);
    }

    // ============================================
    // Admin Functions - Fee Management
    // ============================================

    /**
     * @notice Set the redemption fee rate
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @param newRedemptionFeeInBPS The new redemption fee in basis points (1 BPS = 0.01%)
     */
    function setRedemptionFeeInBPS(uint256 newRedemptionFeeInBPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validateFeeBPS(newRedemptionFeeInBPS, MAX_REDEEM_FEE_BPS);
        uint256 oldFee = redemptionFeeInBPS;
        redemptionFeeInBPS = newRedemptionFeeInBPS;
        emit RedemptionFeeUpdated(oldFee, newRedemptionFeeInBPS);
    }

    /**
     * @notice Set the mint fee rate
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @param newMintFeeInBPS The new mint fee in basis points (1 BPS = 0.01%)
     */
    function setMintFeeInBPS(uint256 newMintFeeInBPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _validateFeeBPS(newMintFeeInBPS, MAX_MINT_FEE_BPS);
        uint256 oldFee = mintFeeInBPS;
        mintFeeInBPS = newMintFeeInBPS;
        emit MintFeeUpdated(oldFee, newMintFeeInBPS);
    }

    // ============================================
    // Admin Functions - Integration Management
    // ============================================

    /**
     * @notice Set the address of the oracle contract
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newOracle The address of the new oracle contract
     */
    function setOracle(address newOracle) external onlyRole(_INTEGRATION_MANAGER_ROLE) {
        _setOracle(newOracle);
    }

    /**
     * @notice Set the address of the custodian
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newCustodian The address of the new custodian
     */
    function setCustodian(address newCustodian) external onlyRole(_INTEGRATION_MANAGER_ROLE) {
        _setCustodian(newCustodian);
    }

    /**
     * @notice Set the address of the yield receiver contract
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newYieldReceiver The address of the new yield receiver contract
     */
    function setYieldReceiver(address newYieldReceiver) external onlyRole(_INTEGRATION_MANAGER_ROLE) {
        _setYieldReceiver(newYieldReceiver);
    }

    /**
     * @notice Internal function to set the address of the oracle contract
     * @param newOracle The address of the new oracle contract
     */
    function _setOracle(address newOracle) internal {
        if (newOracle == address(0)) revert CommonErrors.ZeroAddress();
        address oldOracle = address(oracle);
        oracle = IOracle(newOracle);
        emit OracleUpdated(oldOracle, newOracle);
    }

    /**
     * @notice Internal function to set the address of the custodian
     * @param newCustodian The address of the new custodian
     */
    function _setCustodian(address newCustodian) internal {
        if (newCustodian == address(0)) revert CommonErrors.ZeroAddress();
        address oldCustodian = custodian;
        custodian = newCustodian;
        emit CustodianUpdated(oldCustodian, newCustodian);
    }

    /**
     * @notice Internal function to set the address of the yield receiver contract
     * @param newYieldReceiver The address of the new yield receiver contract
     */
    function _setYieldReceiver(address newYieldReceiver) internal {
        if (newYieldReceiver == address(0)) revert CommonErrors.ZeroAddress();
        address oldYieldReceiver = address(yieldReceiver);
        yieldReceiver = IYieldProcessor(newYieldReceiver);
        emit YieldReceiverUpdated(oldYieldReceiver, newYieldReceiver);
    }

    /**
     * @notice Set the address of the treasury
     * @dev Only callable by _INTEGRATION_MANAGER_ROLE
     * @param newTreasury The address of the new treasury
     */
    function setTreasury(address newTreasury) external onlyRole(_INTEGRATION_MANAGER_ROLE) {
        _setTreasury(newTreasury);
    }

    /**
     * @notice Internal function to set the address of the treasury
     * @param newTreasury The address of the new treasury
     */
    function _setTreasury(address newTreasury) internal {
        if (newTreasury == address(0)) revert CommonErrors.ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Validate that fee percentage is within acceptable range
     * @dev Internal function to consolidate BPS validation logic (DRY principle)
     * @param bps The fee percentage in basis points to validate
     * @param maxBps The maximum allowed fee percentage in basis points
     */
    function _validateFeeBPS(uint256 bps, uint256 maxBps) internal pure {
        if (bps > maxBps) revert FeeTooHigh(bps, maxBps);
    }

    // ============================================
    // Admin Functions - Whitelist Management
    // ============================================

    /**
     * @notice Add an address to the whitelist, allowing them to mint and redeem iTRY
     * @dev Only callable by _WHITELIST_MANAGER_ROLE
     * @param target The address to whitelist
     */
    function addToWhitelist(address target) external onlyRole(_WHITELIST_MANAGER_ROLE) {
        _grantRole(_WHITELISTED_USER_ROLE, target);
    }

    /**
     * @notice Remove an address from the whitelist, preventing them from minting and redeeming iTRY
     * @dev Only callable by _WHITELIST_MANAGER_ROLE
     * @param target The address to remove from whitelist
     */
    function removeFromWhitelist(address target) external onlyRole(_WHITELIST_MANAGER_ROLE) {
        _revokeRole(_WHITELISTED_USER_ROLE, target);
    }

    // ============================================
    // Internal Functions - Token Operations
    // ============================================

    /**
     * @notice Internal function to mint iTRY tokens
     * @dev Updates total issued accounting and calls the iTRY token mint function
     * @param receiver The address to receive the minted tokens
     * @param amount The amount of iTRY tokens to mint
     */
    function _mint(address receiver, uint256 amount) internal {
        _totalIssuedITry += amount;
        iTryToken.mint(receiver, amount);
    }

    /**
     * @notice Internal function to burn iTRY tokens
     * @dev Updates total issued accounting and calls the iTRY token burn function
     * @param from The address whose tokens will be burned
     * @param amount The amount of iTRY tokens to burn
     */
    function _burn(address from, uint256 amount) internal {
        // Burn user's iTRY tokens
        _totalIssuedITry -= amount;
        iTryToken.burnFrom(from, amount);
    }

    // ============================================
    // Internal Functions - Collateral Management
    // ============================================

    /**
     * @notice Internal function to transfer DLF collateral from user to vault and fees to treasury
     * @dev Updates total DLF under custody and transfers tokens
     * @param from The address providing the DLF tokens
     * @param dlfAmount The net amount of DLF to transfer to the vault (after fees)
     * @param feeAmount The fee amount to transfer to treasury
     */
    function _transferIntoVault(address from, uint256 dlfAmount, uint256 feeAmount) internal {
        _totalDLFUnderCustody += dlfAmount;
        // Transfer net DLF amount to buffer pool
        if (!collateralToken.transferFrom(from, address(liquidityVault), dlfAmount)) {
            revert CommonErrors.TransferFailed();
        }

        if (feeAmount > 0) {
            // Transfer fee to treasury
            if (!collateralToken.transferFrom(from, treasury, feeAmount)) {
                revert CommonErrors.TransferFailed();
            }
            emit FeeProcessed(from, treasury, feeAmount);
        }
    }

    /**
     * @notice Internal function to process redemption from the buffer vault
     * @dev Updates total DLF under custody and instructs vault to transfer tokens
     * @param receiver The address to receive the DLF tokens
     * @param receiveAmount The net amount of DLF to transfer (after fees)
     * @param feeAmount The fee amount to transfer to treasury
     */
    function _redeemFromVault(address receiver, uint256 receiveAmount, uint256 feeAmount) internal {
        _totalDLFUnderCustody -= (receiveAmount + feeAmount);

        liquidityVault.processTransfer(receiver, receiveAmount);

        if (feeAmount > 0) {
            liquidityVault.processTransfer(treasury, feeAmount);
        }
    }

    /**
     * @notice Internal function to process redemption via custodian transfer request
     * @dev Emits events for off-chain custodian to process transfers manually
     * @param receiver The address to receive the DLF tokens
     * @param receiveAmount The net amount of DLF to transfer (after fees)
     * @param feeAmount The fee amount to transfer to treasury
     */
    function _redeemFromCustodian(address receiver, uint256 receiveAmount, uint256 feeAmount) internal {
        _totalDLFUnderCustody -= (receiveAmount + feeAmount);

        // Signal that fast access vault needs top-up from custodian
        uint256 topUpAmount = receiveAmount + feeAmount;
        emit FastAccessVaultTopUpRequested(topUpAmount);

        if (feeAmount > 0) {
            // Emit event for off-chain custodian to process
            emit CustodianTransferRequested(treasury, feeAmount);
        }

        // Emit event for off-chain custodian to process
        emit CustodianTransferRequested(receiver, receiveAmount);
    }

    // ============================================
    // Internal Functions - Fee Calculations
    // ============================================

    /**
     * @notice Calculate the mint fee for a given amount
     * @dev Fee = amount * mintFeeInBPS / 10000
     * @param amount The amount to calculate fee on
     * @return feeAmount The calculated fee amount
     */
    function _calculateMintFee(uint256 amount) internal view returns (uint256 feeAmount) {
        // Account for mint fee if configured
        if (mintFeeInBPS > 0) {
            feeAmount = amount * mintFeeInBPS / 10000;
            return feeAmount == 0 ? 1 : feeAmount; // avoid round-down to zero
        } else {
            return 0;
        }
    }

    /**
     * @notice Calculate the redemption fee for a given amount
     * @dev Fee = amount * redemptionFeeInBPS / 10000
     * @param amount The amount to calculate fee on
     * @return feeAmount The calculated fee amount
     */
    function _calculateRedemptionFee(uint256 amount) internal view returns (uint256) {
        // Account for redemption fee if configured
        if (redemptionFeeInBPS == 0) {
            return 0;
        }

        uint256 feeAmount = amount * redemptionFeeInBPS / 10000;
        return feeAmount == 0 ? 1 : feeAmount; // avoid round-down to zero
    }
}
