// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IYieldProcessor
 * @author Inverter Network
 * @notice Interface for contracts that process and distribute yield from the iTRY protocol
 * @dev This interface defines the standard method for yield processing contracts to receive
 *      and handle newly generated yield. Implementations can distribute yield in various ways:
 *      - Direct forwarding to a recipient address
 *      - Distribution across multiple stakeholders
 *      - Conversion to other tokens or protocols
 *      - Staking or liquidity provision
 *
 *      The iTryIssuer contract calls `processNewYield` when accumulated yield is minted,
 *      transferring the yield tokens to the processor contract before calling this function.
 *
 * @custom:security-contact security@inverter.network
 */
interface IYieldProcessor {
    // ============================================
    // Custom Errors
    // ============================================

    /// @notice Thrown when the yield recipient is not set
    error RecipientNotSet();

    // ============================================
    // Functions
    // ============================================

    /**
     * @notice Processes newly generated yield tokens
     * @dev This function is called by the iTryIssuer contract after minting yield tokens.
     *      The implementing contract should already have received the yield tokens before
     *      this function is called. Implementations must handle the yield appropriately
     *      according to their specific distribution logic.
     *
     * @param _newYieldAmount The amount of yield tokens that have been generated and should be processed
     *
     * Requirements:
     * - Implementation should validate that `_newYieldAmount` is greater than zero
     * - Implementation should ensure it has sufficient balance to process the yield
     * - Implementation should handle any distribution logic (transfers, conversions, etc.)
     * - Implementation should emit appropriate events for tracking yield processing
     *
     * @custom:example YieldForwarder implements this by transferring the entire amount to a recipient
     * @custom:example A more complex implementation might split yield across multiple parties
     */
    function processNewYield(uint256 _newYieldAmount) external;
}
