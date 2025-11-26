// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockStakediTryCrosschain
 * @notice Minimal mock for StakediTryCrosschain used in wiTryVaultComposer unit tests
 * @dev Simulates vault behavior with configurable return values
 *      Extends MockERC20 to provide ERC20 functionality (approve, transfer, etc.)
 *      No role checks or complex logic - just returns values and transfers assets
 */
contract MockStakediTryCrosschain is MockERC20 {
    IERC20 public asset;
    uint256 public nextReturnValue = 100e18; // configurable return amount

    constructor(IERC20 _asset) MockERC20("MockVault", "mVault") {
        asset = _asset;
    }

    /**
     * @notice Mock cooldownSharesByComposer - transfers assets and returns configured value
     * @param shares Amount of shares (unused in mock)
     * @param redeemer Address of redeemer (unused in mock)
     * @return assets Amount of assets transferred
     */
    function cooldownSharesByComposer(uint256 shares, address redeemer) external returns (uint256 assets) {
        assets = nextReturnValue;
        // Transfer assets to caller (wiTryVaultComposer) to simulate vault behavior
        if (assets > 0) {
            asset.transfer(msg.sender, assets);
        }
        return assets;
    }

    /**
     * @notice Mock fastRedeemThroughComposer - transfers assets and returns configured value
     * @param shares Amount of shares (unused in mock)
     * @param crosschainReceiver Address of receiver (unused in mock)
     * @param owner Address of owner (unused in mock)
     * @return assets Amount of assets transferred
     */
    function fastRedeemThroughComposer(uint256 shares, address crosschainReceiver, address owner)
        external
        returns (uint256 assets)
    {
        assets = nextReturnValue;
        // Transfer assets to caller (wiTryVaultComposer) to simulate vault behavior
        if (assets > 0) {
            asset.transfer(msg.sender, assets);
        }
        return assets;
    }

    /**
     * @notice Mock unstakeThroughComposer - transfers assets and returns configured value
     * @param receiver Address of receiver (unused in mock)
     * @return assets Amount of assets transferred
     */
    function unstakeThroughComposer(address receiver) external returns (uint256 assets) {
        assets = nextReturnValue;
        // Transfer assets to caller (wiTryVaultComposer) to simulate vault behavior
        if (assets > 0) {
            asset.transfer(msg.sender, assets);
        }
        return assets;
    }

    /**
     * @notice Configure the return value for mock functions
     * @param value Amount to return on next call
     */
    function setNextReturnValue(uint256 value) external {
        nextReturnValue = value;
    }
}
