// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title MockLayerZeroEndpoint
 * @notice Minimal mock for LayerZero Endpoint used in wiTryVaultComposer unit tests
 * @dev Only implements eid() - the bare minimum needed for VaultComposerSync constructor
 */
contract MockLayerZeroEndpoint {
    uint32 public constant EID = 30101; // Sepolia EID

    /**
     * @notice Returns the endpoint ID
     */
    function eid() external pure returns (uint32) {
        return EID;
    }

    /**
     * @notice Mock setDelegate - does nothing
     * @param _delegate Delegate address (unused)
     */
    function setDelegate(address _delegate) external {
        // No-op for testing
    }
}
