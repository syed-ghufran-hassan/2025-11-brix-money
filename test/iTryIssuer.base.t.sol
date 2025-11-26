// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/protocol/iTryIssuer.sol";
import "../src/token/iTRY/interfaces/IiTryToken.sol";
import "../src/protocol/interfaces/IFastAccessVault.sol";
import "../src/protocol/periphery/IOracle.sol";
import "../src/protocol/periphery/IYieldProcessor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title Mock iTRY Token for Testing
 * @notice Simplified iTRY token with controller-based mint/burn
 */
contract MockITryToken is ERC20 {
    address public controller;

    constructor() ERC20("iTRY Token", "iTRY") {}

    modifier onlyController() {
        require(msg.sender == controller, "Only controller");
        _;
    }

    function setController(address _controller) external {
        controller = _controller;
    }

    function mint(address to, uint256 amount) external onlyController {
        _mint(to, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyController {
        _burn(from, amount);
    }
}

/**
 * @title Mock Oracle for Testing
 * @notice Returns configurable NAV price
 */
contract MockOracle is IOracle {
    uint256 private _price;
    bool private _shouldRevert;

    constructor(uint256 initialPrice) {
        _price = initialPrice;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    function price() external view returns (uint256) {
        require(!_shouldRevert, "Oracle: revert enabled");
        return _price;
    }
}

/**
 * @title Mock Fast Access Vault for Testing
 * @notice Simulates liquidity vault with controllable balance
 */
contract MockFastAccessVault is IFastAccessVault {
    IERC20 public vaultToken;
    uint256 private _availableBalance;
    address private _issuerContract;
    uint256 private _targetBufferPercentageBPS;
    uint256 private _minimumBufferBalance;

    struct TransferCall {
        address recipient;
        uint256 amount;
    }
    TransferCall[] public transferCalls;

    function setVaultToken(address token) external {
        vaultToken = IERC20(token);
    }

    function setAvailableBalance(uint256 balance) external {
        _availableBalance = balance;
    }

    function getAvailableBalance() external view returns (uint256) {
        return _availableBalance;
    }

    function getIssuerContract() external view returns (address) {
        return _issuerContract;
    }

    function getTargetBufferPercentage() external view returns (uint256) {
        return _targetBufferPercentageBPS;
    }

    function getMinimumBufferBalance() external view returns (uint256) {
        return _minimumBufferBalance;
    }

    function setIssuerContract(address newIssuerContract) external {
        _issuerContract = newIssuerContract;
    }

    function setCustodian(address newCustodian) external {
        // Mock implementation - does nothing for tests
    }

    function processTransfer(address recipient, uint256 amount) external {
        require(_availableBalance >= amount, "Insufficient vault balance");
        _availableBalance -= amount;
        transferCalls.push(TransferCall({recipient: recipient, amount: amount}));
        // In a real vault, this would transfer tokens
    }

    function rebalanceFunds() external {
        // Mock implementation - do nothing
    }

    function setTargetBufferPercentage(uint256 newTargetPercentageBPS) external {
        _targetBufferPercentageBPS = newTargetPercentageBPS;
    }

    function setMinimumBufferBalance(uint256 newMinimumBufferBalance) external {
        _minimumBufferBalance = newMinimumBufferBalance;
    }

    // Test helper functions
    function getTransferCallsCount() external view returns (uint256) {
        return transferCalls.length;
    }

    function getTransferCall(uint256 index) external view returns (address recipient, uint256 amount) {
        TransferCall memory call = transferCalls[index];
        return (call.recipient, call.amount);
    }

    function clearTransferCalls() external {
        delete transferCalls;
    }
}

/**
 * @title Mock Yield Processor for Testing
 * @notice Tracks yield processing calls
 */
contract MockYieldProcessor is IYieldProcessor {
    struct YieldCall {
        uint256 amount;
        uint256 timestamp;
    }
    YieldCall[] public yieldCalls;
    bool private _shouldRevert;

    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    function processNewYield(uint256 amount) external {
        require(!_shouldRevert, "YieldProcessor: revert enabled");
        yieldCalls.push(YieldCall({amount: amount, timestamp: block.timestamp}));
    }

    function getYieldCallsCount() external view returns (uint256) {
        return yieldCalls.length;
    }

    function getYieldCall(uint256 index) external view returns (uint256 amount, uint256 timestamp) {
        YieldCall memory call = yieldCalls[index];
        return (call.amount, call.timestamp);
    }

    function clearYieldCalls() external {
        delete yieldCalls;
    }
}

/**
 * @title Base Test Contract for iTryIssuer
 * @notice Provides common setup and helpers for all iTryIssuer tests
 */
abstract contract iTryIssuerBaseTest is Test {
    // Contracts
    iTryIssuer public issuer;
    MockITryToken public iTryToken;
    MockERC20 public collateralToken;
    MockOracle public oracle;
    IFastAccessVault public vault;
    MockYieldProcessor public yieldProcessor;

    // Test accounts
    address public admin;
    address public whitelistManager;
    address public whitelistedUser1;
    address public whitelistedUser2;
    address public nonWhitelisted;
    address public treasury;
    address public custodian;

    // Constants
    uint256 constant INITIAL_DLF_SUPPLY = 10_000_000e18;
    uint256 constant INITIAL_NAV_PRICE = 1e18; // 1:1 ratio
    uint256 constant DEFAULT_MINT_FEE_BPS = 50; // 0.5%
    uint256 constant DEFAULT_REDEMPTION_FEE_BPS = 30; // 0.3%
    uint256 constant BPS_DENOMINATOR = 10_000;

    // Role constants (matching iTryIssuer)
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");
    bytes32 constant WHITELISTED_USER_ROLE = keccak256("WHITELISTED_USER_ROLE");

    // Events (for expectEmit)
    event ITRYIssued(
        address indexed recipient, uint256 dlfAmount, uint256 iTRYAmount, uint256 navPrice, uint256 mintFee
    );
    event ITRYRedeemed(
        address indexed recipient, uint256 iTRYAmount, uint256 dlfAmount, bool fromBuffer, uint256 redemptionFee
    );
    event YieldDistributed(uint256 amount, address indexed receiver, uint256 totalCollateralValue);
    event FeeProcessed(address indexed from, address indexed to, uint256 amount);
    event CustodianTransferRequested(address indexed recipient, uint256 amount);
    event RedemptionFeeUpdated(uint256 oldFee, uint256 newFee);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);
    event UserWhitelisted(address indexed user, bool status);

    function setUp() public virtual {
        // Create test accounts
        admin = makeAddr("admin");
        whitelistManager = makeAddr("whitelistManager");
        whitelistedUser1 = makeAddr("whitelistedUser1");
        whitelistedUser2 = makeAddr("whitelistedUser2");
        nonWhitelisted = makeAddr("nonWhitelisted");
        treasury = makeAddr("treasury");
        custodian = makeAddr("custodian");

        // Label accounts for better trace output
        vm.label(admin, "Admin");
        vm.label(whitelistManager, "WhitelistManager");
        vm.label(whitelistedUser1, "WhitelistedUser1");
        vm.label(whitelistedUser2, "WhitelistedUser2");
        vm.label(nonWhitelisted, "NonWhitelisted");
        vm.label(treasury, "Treasury");
        vm.label(custodian, "Custodian");

        // Deploy mock contracts
        iTryToken = new MockITryToken();
        collateralToken = new MockERC20("DLF Token", "DLF");
        oracle = new MockOracle(INITIAL_NAV_PRICE);
        yieldProcessor = new MockYieldProcessor();

        vm.label(address(iTryToken), "iTryToken");
        vm.label(address(collateralToken), "CollateralToken");
        vm.label(address(oracle), "Oracle");
        vm.label(address(yieldProcessor), "YieldProcessor");

        // Deploy iTryIssuer (vault is deployed internally by iTryIssuer)
        issuer = new iTryIssuer(
            address(iTryToken),
            address(collateralToken),
            address(oracle),
            treasury,
            address(yieldProcessor),
            custodian,
            admin,
            0, // initialIssued
            0, // initialDLFUnderCustody
            500, // vaultTargetPercentageBPS (5%)
            50_000e18 // vaultMinimumBalance
        );
        vm.label(address(issuer), "Issuer");

        // Get the vault that was created by the issuer
        vault = issuer.liquidityVault();
        vm.label(address(vault), "Vault");

        // Grant iTryToken mint/burn permission to issuer
        iTryToken.setController(address(issuer));

        // Set up roles and fees
        vm.startPrank(admin);
        issuer.setMintFeeInBPS(DEFAULT_MINT_FEE_BPS);
        issuer.setRedemptionFeeInBPS(DEFAULT_REDEMPTION_FEE_BPS);
        issuer.grantRole(WHITELIST_MANAGER_ROLE, whitelistManager);
        vm.stopPrank();

        // Whitelist users
        vm.startPrank(whitelistManager);
        issuer.addToWhitelist(whitelistedUser1);
        issuer.addToWhitelist(whitelistedUser2);
        vm.stopPrank();

        // Mint collateral to whitelisted users
        collateralToken.mint(whitelistedUser1, INITIAL_DLF_SUPPLY);
        collateralToken.mint(whitelistedUser2, INITIAL_DLF_SUPPLY);

        // Approve issuer to spend collateral
        vm.prank(whitelistedUser1);
        collateralToken.approve(address(issuer), type(uint256).max);

        vm.prank(whitelistedUser2);
        collateralToken.approve(address(issuer), type(uint256).max);

        // Fund vault with some initial liquidity
        collateralToken.mint(address(vault), 1_000_000e18);
    }

    // ============================================
    // Helper Functions
    // ============================================

    /**
     * @notice Helper to mint iTRY tokens
     * @param user The user performing the mint
     * @param dlfAmount The amount of DLF to deposit
     * @param minAmountOut Minimum iTRY output
     * @return iTRYAmount The amount of iTRY minted
     */
    function _mintITry(address user, uint256 dlfAmount, uint256 minAmountOut) internal returns (uint256 iTRYAmount) {
        vm.prank(user);
        return issuer.mintFor(user, dlfAmount, minAmountOut);
    }

    /**
     * @notice Helper to redeem iTRY tokens
     * @param user The user performing the redemption
     * @param iTRYAmount The amount of iTRY to redeem
     * @param minAmountOut Minimum DLF output
     * @return fromBuffer Whether redemption was from vault
     */
    function _redeemITry(address user, uint256 iTRYAmount, uint256 minAmountOut) internal returns (bool fromBuffer) {
        vm.prank(user);
        return issuer.redeemFor(user, iTRYAmount, minAmountOut);
    }

    /**
     * @notice Helper to set NAV price
     * @param newPrice The new oracle price
     */
    function _setNAVPrice(uint256 newPrice) internal {
        oracle.setPrice(newPrice);
    }

    /**
     * @notice Helper to process accumulated yield
     * @return yieldMinted The amount of yield minted
     */
    function _processYield() internal returns (uint256 yieldMinted) {
        vm.prank(admin);
        return issuer.processAccumulatedYield();
    }

    /**
     * @notice Calculate expected mint fee
     * @param dlfAmount The DLF amount
     * @return feeAmount The calculated fee
     */
    function _calculateMintFee(uint256 dlfAmount) internal view returns (uint256 feeAmount) {
        uint256 mintFee = issuer.mintFeeInBPS();
        if (mintFee > 0) {
            return (dlfAmount * mintFee) / BPS_DENOMINATOR;
        }
        return 0;
    }

    /**
     * @notice Calculate expected redemption fee
     * @param grossDlfAmount The gross DLF amount
     * @return feeAmount The calculated fee
     */
    function _calculateRedemptionFee(uint256 grossDlfAmount) internal view returns (uint256 feeAmount) {
        uint256 redemptionFee = issuer.redemptionFeeInBPS();
        if (redemptionFee > 0) {
            return (grossDlfAmount * redemptionFee) / BPS_DENOMINATOR;
        }
        return 0;
    }

    /**
     * @notice Calculate expected iTRY output for minting
     * @param dlfAmount The DLF input amount
     * @return iTRYAmount The expected iTRY output
     */
    function _calculateMintOutput(uint256 dlfAmount) internal view returns (uint256 iTRYAmount) {
        uint256 navPrice = oracle.price();
        uint256 feeAmount = _calculateMintFee(dlfAmount);
        uint256 netDlfAmount = dlfAmount - feeAmount;
        return (netDlfAmount * navPrice) / 1e18;
    }

    /**
     * @notice Calculate expected DLF output for redemption
     * @param iTRYAmount The iTRY input amount
     * @return netDlfAmount The expected net DLF output
     * @return grossDlfAmount The gross DLF before fees
     */
    function _calculateRedeemOutput(uint256 iTRYAmount)
        internal
        view
        returns (uint256 netDlfAmount, uint256 grossDlfAmount)
    {
        uint256 navPrice = oracle.price();
        grossDlfAmount = (iTRYAmount * 1e18) / navPrice;
        uint256 feeAmount = _calculateRedemptionFee(grossDlfAmount);
        netDlfAmount = grossDlfAmount - feeAmount;
    }

    /**
     * @notice Set vault balance for testing vault/custodian paths
     * @param balance The vault balance to set
     */
    function _setVaultBalance(uint256 balance) internal {
        // Get current vault balance
        uint256 currentBalance = collateralToken.balanceOf(address(vault));

        if (balance > currentBalance) {
            // Need to add tokens to vault
            uint256 amountToAdd = balance - currentBalance;
            collateralToken.mint(address(vault), amountToAdd);
        } else if (balance < currentBalance) {
            // Need to remove tokens from vault
            uint256 amountToRemove = currentBalance - balance;
            // Use vm.prank to burn tokens from the vault
            vm.prank(address(vault));
            collateralToken.transfer(address(0xdead), amountToRemove);
        }
        // If balance == currentBalance, do nothing
    }

    /**
     * @notice Get the vault's current DLF balance
     */
    function _getVaultBalance() internal view returns (uint256) {
        return collateralToken.balanceOf(address(vault));
    }

    /**
     * @notice Clear yield processor call history
     */
    function _clearYieldCalls() internal {
        yieldProcessor.clearYieldCalls();
    }

    /**
     * @notice Get current total issued iTRY
     */
    function _getTotalIssued() internal view returns (uint256) {
        return issuer.getTotalIssuedITry();
    }

    /**
     * @notice Get current total DLF under custody
     */
    function _getTotalCustody() internal view returns (uint256) {
        return issuer.getCollateralUnderCustody();
    }
}
