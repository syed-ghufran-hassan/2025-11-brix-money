// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title IOracle
 * @notice Interface for price oracles that provide exchange rates for iTRY system
 * @dev Implementations must provide a price feed for converting between iTRY and collateral tokens
 */
interface IOracle {
    /**
     * @notice Returns the current price of 1 unit of iTRY quoted in 1 unit of collateral token (DLF)
     * @dev MUST return the price denominated in 18 decimals (e.g., 1e18 = 1:1 ratio)
     * @dev MUST perform all necessary validation checks and revert if:
     *      - The price data is stale or invalid
     *      - The oracle feed is unavailable
     *      - Any integrity checks fail
     * @dev MUST NOT return zero or invalid prices
     * @return The price in 18 decimal precision
     *
     * @custom:implementation-notes
     * For Redstone Oracle implementations:
     * - Inherit from either "MainDemoConsumerBase.sol" (testnet) or "PrimaryProdDataServiceConsumerBase.sol" (mainnet)
     * - Use `getOracleNumericValueFromTxMsg(bytes32 feedName)` within the price() implementation
     * - Ensure proper signature verification is performed by the Redstone base contract
     */
    function price() external view returns (uint256);
}
