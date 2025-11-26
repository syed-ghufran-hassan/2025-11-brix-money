// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFastAccessVault} from "./interfaces/IFastAccessVault.sol";
import {IiTryIssuer} from "./interfaces/IiTryIssuer.sol";
import {CommonErrors} from "./periphery/CommonErrors.sol";

/**
 * @title FastAccessVault
 * @author Inverter Network
 * @notice Liquidity buffer vault for instant iTRY redemptions without custodian delays
 * @dev This contract maintains a configurable percentage of total DLF collateral to enable
 *      instant redemptions. It automatically rebalances between itself and the custodian to
 *      maintain optimal liquidity levels.
 *
 *      Key features:
 *      - Holds buffer of DLF tokens for instant redemptions
 *      - Automatic rebalancing based on target percentage of AUM
 *      - Minimum balance floor to ensure always-available liquidity
 *      - Fixed reference to authorized issuer contract for access control
 *      - Emergency token rescue functionality
 *
 *      The vault uses a two-tier sizing strategy:
 *      1. Target percentage: Buffer = AUM * targetBufferPercentageBPS / 10000
 *      2. Minimum balance: Buffer = max(calculated_target, minimumExpectedBalance)
 *
 * @custom:security-contact security@inverter.network
 */
contract FastAccessVault is IFastAccessVault, Ownable, ReentrancyGuard {
    // ============================================
    using SafeERC20 for IERC20;

    // ============================================
    // Constants
    // ============================================

    /// @notice Maximum buffer percentage in basis points (100% = 10000 BPS)
    uint256 public constant MAX_BUFFER_PCT_BPS = 10000;

    // ============================================
    // State Variables
    // ============================================

    /// @notice The vault token (DLF) that this contract holds for redemptions
    IERC20 public immutable _vaultToken;

    /// @notice The authorized issuer contract that can withdraw from the vault
    IiTryIssuer public immutable _issuerContract;

    /// @notice The custodian address for requesting/transferring excess funds
    address public custodian;

    /// @notice Target buffer size as percentage of total AUM in basis points (e.g., 500 = 5%)
    uint256 public targetBufferPercentageBPS;

    /// @notice Minimum balance to target regardless of percentage calculation
    uint256 public minimumExpectedBalance;

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Restricts function access to the authorized issuer contract only
     */
    modifier onlyIssuer() {
        if (msg.sender != address(_issuerContract)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the FastAccessVault with token, issuer, custodian, and buffer parameters
     * @param __vaultToken Address of the vault token (DLF)
     * @param __issuerContract Address of the authorized issuer contract
     * @param _custodian Address of the custodian (where transfer requests are sent)
     * @param _initialTargetPercentageBPS Initial target buffer percentage in basis points (max 10000 = 100%)
     * @param _minimumExpectedBalance Initial minimum balance to maintain in vault
     * @param _initialAdmin Address to receive ownership of the vault
     */
    constructor(
        address __vaultToken,
        address __issuerContract,
        address _custodian,
        uint256 _initialTargetPercentageBPS,
        uint256 _minimumExpectedBalance,
        address _initialAdmin
    ) {
        if (__vaultToken == address(0)) revert CommonErrors.ZeroAddress();
        if (__issuerContract == address(0)) revert CommonErrors.ZeroAddress();
        if (_custodian == address(0)) revert CommonErrors.ZeroAddress();
        if (_initialAdmin == address(0)) revert CommonErrors.ZeroAddress();

        _validateBufferPercentageBPS(_initialTargetPercentageBPS);

        _vaultToken = IERC20(__vaultToken);
        _issuerContract = IiTryIssuer(__issuerContract);
        custodian = _custodian;
        targetBufferPercentageBPS = _initialTargetPercentageBPS;
        minimumExpectedBalance = _minimumExpectedBalance;

        // Transfer ownership to the initial admin
        transferOwnership(_initialAdmin);
    }

    // ============================================
    // View Functions
    // ============================================

    /// @inheritdoc IFastAccessVault
    function getAvailableBalance() public view returns (uint256) {
        return _vaultToken.balanceOf(address(this));
    }

    /// @inheritdoc IFastAccessVault
    function getIssuerContract() external view returns (address) {
        return address(_issuerContract);
    }

    /// @inheritdoc IFastAccessVault
    function getTargetBufferPercentage() external view returns (uint256) {
        return targetBufferPercentageBPS;
    }

    /// @inheritdoc IFastAccessVault
    function getMinimumBufferBalance() external view returns (uint256) {
        return minimumExpectedBalance;
    }

    // ============================================
    // State-Changing Functions - Transfer Operations
    // ============================================

    /// @inheritdoc IFastAccessVault
    function processTransfer(address _receiver, uint256 _amount) external onlyIssuer {
        if (_receiver == address(0)) revert CommonErrors.ZeroAddress();
        if (_receiver == address(this)) revert InvalidReceiver(_receiver);
        if (_amount == 0) revert CommonErrors.ZeroAmount();

        uint256 currentBalance = _vaultToken.balanceOf(address(this));
        if (currentBalance < _amount) {
            revert InsufficientBufferBalance(_amount, currentBalance);
        }

        if (!_vaultToken.transfer(_receiver, _amount)) {
            revert CommonErrors.TransferFailed();
        }
        emit TransferProcessed(_receiver, _amount, (currentBalance - _amount));
    }

    // ============================================
    // State-Changing Functions - Rebalancing
    // ============================================

    /// @inheritdoc IFastAccessVault
    function rebalanceFunds() external {
        uint256 aumReferenceValue = _issuerContract.getCollateralUnderCustody();
        uint256 targetBalance = _calculateTargetBufferBalance(aumReferenceValue);
        uint256 currentBalance = _vaultToken.balanceOf(address(this));

        if (currentBalance < targetBalance) {
            uint256 needed = targetBalance - currentBalance;
            // Emit event for off-chain custodian to process
            emit TopUpRequestedFromCustodian(address(custodian), needed, targetBalance);
        } else if (currentBalance > targetBalance) {
            uint256 excess = currentBalance - targetBalance;
            if (!_vaultToken.transfer(custodian, excess)) {
                revert CommonErrors.TransferFailed();
            }
            emit ExcessFundsTransferredToCustodian(address(custodian), excess, targetBalance);
        }
    }

    // ============================================
    // Admin Functions - Configuration
    // ============================================

    /// @inheritdoc IFastAccessVault
    function setTargetBufferPercentage(uint256 newTargetPercentageBPS) external onlyOwner {
        _validateBufferPercentageBPS(newTargetPercentageBPS);

        uint256 oldPercentageBPS = targetBufferPercentageBPS;
        targetBufferPercentageBPS = newTargetPercentageBPS;
        emit TargetBufferPercentageUpdated(oldPercentageBPS, newTargetPercentageBPS);
    }

    /// @inheritdoc IFastAccessVault
    function setMinimumBufferBalance(uint256 newMinimumBufferBalance) external onlyOwner {
        uint256 oldMinimumBalance = minimumExpectedBalance;
        minimumExpectedBalance = newMinimumBufferBalance;
        emit MinimumBufferBalanceUpdated(oldMinimumBalance, newMinimumBufferBalance);
    }

    // ============================================
    // Admin Functions - Emergency/Rescue
    // ============================================

    /**
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

        emit TokenRescued(token, to, amount);
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @notice Calculate the target buffer balance based on reference AUM
     * @dev Uses the larger of: (referenceAUM * targetPercentage) or minimumExpectedBalance
     * @param _referenceAUM The total assets under management to base calculation on
     * @return The calculated target buffer balance
     */
    function _calculateTargetBufferBalance(uint256 _referenceAUM) internal view returns (uint256) {
        uint256 targetBufferBalance = (_referenceAUM * targetBufferPercentageBPS) / 10000;
        return (targetBufferBalance < minimumExpectedBalance) ? minimumExpectedBalance : targetBufferBalance;
    }

    /**
     * @notice Validate that buffer percentage is within acceptable range
     * @dev Internal function to consolidate BPD validation logic (DRY principle)
     * @param bps The buffer percentage in basis points to validate
     */
    function _validateBufferPercentageBPS(uint256 bps) internal pure {
        if (bps > MAX_BUFFER_PCT_BPS) revert PercentageTooHigh(bps, MAX_BUFFER_PCT_BPS);
    }

    /**
     * @notice Update the custodian address
     * @dev Only callable by owner
     * @param newCustodian The new custodian address
     */
    function setCustodian(address newCustodian) external onlyOwner {
        if (newCustodian == address(0)) revert CommonErrors.ZeroAddress();

        address oldCustodian = custodian;
        custodian = newCustodian;
        emit CustodianUpdated(oldCustodian, newCustodian);
    }
}
