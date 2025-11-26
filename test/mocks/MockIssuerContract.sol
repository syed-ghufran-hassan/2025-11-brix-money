// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IiTryIssuer} from "../../src/protocol/interfaces/IiTryIssuer.sol";
import {IFastAccessVault} from "../../src/protocol/interfaces/IFastAccessVault.sol";

/**
 * @title MockIssuerContract
 * @notice Mock implementation of IiTryIssuer for testing FastAccessVault
 * @dev Only implements methods needed for vault testing
 */
contract MockIssuerContract is IiTryIssuer {
    uint256 private _collateralUnderCustody;
    address public vault;

    constructor(uint256 initialCollateral) {
        _collateralUnderCustody = initialCollateral;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function setCollateralUnderCustody(uint256 amount) external {
        _collateralUnderCustody = amount;
    }

    function getCollateralUnderCustody() external view returns (uint256) {
        return _collateralUnderCustody;
    }

    // Function to test vault.processTransfer as the issuer
    function callProcessTransfer(address receiver, uint256 amount) external {
        IFastAccessVault(vault).processTransfer(receiver, amount);
    }

    // Stub implementations for interface compliance (not used in vault tests)
    function getTotalIssuedITry() external pure returns (uint256) {
        return 0;
    }

    function previewMint(uint256 /* dlfAmount */) external pure returns (uint256 iTRYAmount) {
        return 0;
    }

    function previewRedeem(uint256 /* iTRYAmount */) external pure returns (uint256 dlfAmount) {
        return 0; // Mock: 1:1 redeeming for simplicity
    }

    function previewAccumulatedYield() external pure returns (uint256) {
        return 0; // Mock: No accumulated yield for simplicity
    }

    function isWhitelistedUser(address /* user */) external pure returns (bool) {
        return true;
    }

    function mintITRY(uint256 /* dlfAmount */, uint256 /* minAmountOut */) external pure returns (uint256 /* iTRYAmount */) {
        revert("Not implemented");
    }

    function mintFor(
        address /* recipient */,
        /* solhint-disable-next-line no-unused-vars */
        uint256 /* dlfAmount */,
        uint256 /* minAmountOut */
    )
        external
        pure
        returns (uint256 /* iTRYAmount */)
    {
        revert("Not implemented");
    }

    function redeemITRY(uint256 /* iTRYAmount */, uint256 /* minAmountOut */) external pure returns (bool /* fromBuffer */) {
        revert("Not implemented");
    }

    function redeemFor(
        address /* recipient */,
        /* solhint-disable-next-line no-unused-vars */
        uint256 /* iTRYAmount */,
        uint256 /* minAmountOut */
    )
        external
        pure
        returns (bool /* fromBuffer */)
    {
        revert("Not implemented");
    }

    function setOracle(address /* newOracle */) external pure {
        revert("Not implemented");
    }

    function setCustodian(address /* newCustodian */) external pure {
        revert("Not implemented");
    }

    function setYieldReceiver(address /* newYieldReceiver */) external pure {
        revert("Not implemented");
    }

    function processAccumulatedYield() external pure returns (uint256 /* yieldMinted */) {
        revert("Not implemented");
    }

    function burnExcessITry(uint256 /* iTRYAmount */) external pure {
        revert("Not implemented");
    }
}
