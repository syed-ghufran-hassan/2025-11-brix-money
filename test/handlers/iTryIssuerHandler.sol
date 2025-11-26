// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../iTryIssuer.base.t.sol";

/**
 * @title iTryIssuer Handler
 * @notice Handler contract for stateful fuzzing / invariant testing
 * @dev Manages state and provides bounded operations for the fuzzer
 */
contract iTryIssuerHandler is iTryIssuerBaseTest {
    // Track call counts for debugging
    uint256 public mintCalls;
    uint256 public redeemCalls;
    uint256 public yieldCalls;
    uint256 public feeChangeCalls;

    // Ghost variables for tracking
    uint256 public ghost_totalMinted;
    uint256 public ghost_totalRedeemed;
    uint256 public ghost_totalYieldProcessed;

    // Actors for operations
    address[] public actors;
    address internal currentActor;

    constructor() {
        // Call setUp from base
        setUp();

        // Create actor addresses
        actors.push(whitelistedUser1);
        actors.push(whitelistedUser2);

        // Set initial actor
        currentActor = whitelistedUser1;
    }

    // ============================================
    // Modifiers
    // ============================================

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        _;
    }

    // ============================================
    // Handler Functions
    // ============================================

    /// @notice Handler for minting iTRY
    /// @dev Bounds: $1 to $100M per operation - production-scale institutional transactions
    function handler_mintFor(uint256 actorIndexSeed, uint256 dlfAmount) public useActor(actorIndexSeed) {
        dlfAmount = bound(dlfAmount, 1e18, 100_000_000e18);

        // Ensure actor has collateral
        collateralToken.mint(currentActor, dlfAmount);
        vm.prank(currentActor);
        collateralToken.approve(address(issuer), dlfAmount);

        // Mint
        try vm.prank(currentActor) {
            uint256 iTRYAmount = issuer.mintFor(currentActor, dlfAmount, 0);

            // Update ghost variables
            ghost_totalMinted += iTRYAmount;
            mintCalls++;
        } catch {
            // Mint can fail for various reasons, that's ok
        }
    }

    /// @notice Handler for redeeming iTRY
    function handler_redeemFor(uint256 actorIndexSeed, uint256 iTRYAmountSeed) public useActor(actorIndexSeed) {
        // Get actor's balance
        uint256 balance = iTryToken.balanceOf(currentActor);

        // Skip if no balance
        if (balance == 0) return;

        // Bound iTRY amount to actor's balance
        uint256 iTRYAmount = bound(iTRYAmountSeed, 1e18, balance);

        // Calculate gross DLF for vault setup
        uint256 navPrice = oracle.price();
        uint256 grossDlf = (iTRYAmount * 1e18) / navPrice;

        // Set vault balance to have enough (force vault path for predictability)
        _setVaultBalance(grossDlf + 1000e18);

        // Redeem
        try vm.prank(currentActor) {
            issuer.redeemFor(currentActor, iTRYAmount, 0);

            // Update ghost variables
            ghost_totalRedeemed += iTRYAmount;
            redeemCalls++;
        } catch {
            // Redeem can fail, that's ok
        }
    }

    /// @notice Handler for processing yield
    function handler_processYield() public {
        // Check if yield is available
        uint256 previewYield = issuer.previewAccumulatedYield();

        if (previewYield > 0) {
            try vm.prank(admin) {
                uint256 yieldMinted = issuer.processAccumulatedYield();

                // Update ghost variables
                ghost_totalYieldProcessed += yieldMinted;
                yieldCalls++;
            } catch {
                // Yield processing can fail, that's ok
            }
        }
    }

    /// @notice Handler for increasing NAV price
    /// @dev Bounds: 0-50% increase - Turkish Lira can rally significantly during stabilization
    function handler_increaseNAV(uint256 priceIncreaseBPS) public {
        priceIncreaseBPS = bound(priceIncreaseBPS, 0, 5000);

        uint256 currentPrice = oracle.price();
        uint256 newPrice = currentPrice + (currentPrice * priceIncreaseBPS) / 10000;

        oracle.setPrice(newPrice);
    }

    /// @notice Handler for decreasing NAV price
    /// @dev Bounds: 0-30% decrease per step - realistic for Turkish Lira crisis scenarios
    function handler_decreaseNAV(uint256 priceDecreaseBPS) public {
        // Turkish Lira historical volatility: Can drop 30%+ in severe crisis
        // Testing 30% per step allows accumulation to 90%+ crashes over multiple operations
        priceDecreaseBPS = bound(priceDecreaseBPS, 0, 3000);

        uint256 currentPrice = oracle.price();
        uint256 decrease = (currentPrice * priceDecreaseBPS) / 10000;

        // Ensure price doesn't go to 0
        uint256 newPrice = currentPrice > decrease ? currentPrice - decrease : currentPrice / 2;

        oracle.setPrice(newPrice);
    }

    /// @notice Handler for changing mint fee
    /// @dev Bounds: 0-10% - tests full operational range of fees
    function handler_setMintFee(uint256 feeInBPS) public {
        // Production operational range: 0-10% covers typical stablecoin fees
        // Allows testing revenue collection at scale
        feeInBPS = bound(feeInBPS, 0, 1000);

        vm.prank(admin);
        issuer.setMintFeeInBPS(feeInBPS);

        feeChangeCalls++;
    }

    /// @notice Handler for changing redemption fee
    /// @dev Bounds: 0-10% - tests full operational range of fees
    function handler_setRedemptionFee(uint256 feeInBPS) public {
        // Production operational range: 0-10%
        feeInBPS = bound(feeInBPS, 0, 1000);

        vm.prank(admin);
        issuer.setRedemptionFeeInBPS(feeInBPS);

        feeChangeCalls++;
    }

    // ============================================
    // Helper Functions for Invariants
    // ============================================

    /// @notice Get total iTRY balance across all actors
    function getTotalActorBalance() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            total += iTryToken.balanceOf(actors[i]);
        }
        return total;
    }

    /// @notice Get yield receiver balance
    function getYieldReceiverBalance() public view returns (uint256) {
        return iTryToken.balanceOf(address(yieldProcessor));
    }

    /// @notice Calculate total circulating supply
    function getTotalCirculatingSupply() public view returns (uint256) {
        return getTotalActorBalance() + getYieldReceiverBalance();
    }

    /// @notice Calculate expected collateral value
    function getExpectedCollateralValue() public view returns (uint256) {
        uint256 custody = issuer.getCollateralUnderCustody();
        uint256 navPrice = oracle.price();
        return (custody * navPrice) / 1e18;
    }
}
