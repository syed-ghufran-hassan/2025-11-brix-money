// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {wiTryVaultComposer} from "../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol";
import {IUnstakeMessenger} from "../../src/token/wiTRY/crosschain/interfaces/IUnstakeMessenger.sol";

/**
 * @title wiTryVaultComposerHarness
 * @notice Test harness contract that exposes internal functions of wiTryVaultComposer for unit testing
 * @dev Extends wiTryVaultComposer and makes internal functions public for direct testing
 */
contract wiTryVaultComposerHarness is wiTryVaultComposer {
    /**
     * @notice Initialize the harness with the same parameters as wiTryVaultComposer
     */
    constructor(address _vault, address _assetOFT, address _shareOFT, address _endpoint)
        wiTryVaultComposer(_vault, _assetOFT, _shareOFT, _endpoint)
    {}

    /**
     * @notice Expose _initiateCooldown for testing
     */
    function exposed_initiateCooldown(bytes32 _redeemer, uint256 _shareAmount) external {
        _initiateCooldown(_redeemer, _shareAmount);
    }

    /**
     * @notice Expose _fastRedeem for testing
     */
    function exposed_fastRedeem(
        bytes32 _redeemer,
        uint256 _shareAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external {
        _fastRedeem(_redeemer, _shareAmount, _sendParam, _refundAddress);
    }

    /**
     * @notice Expose _redeemAndSend for testing
     */
    function exposed_redeemAndSend(bytes32 _redeemer, uint256 _shareAmount, SendParam memory _sendParam, address _refundAddress)
        external
    {
        _redeemAndSend(_redeemer, _shareAmount, _sendParam, _refundAddress);
    }

    /**
     * @notice Expose _refund for testing
     */
    function exposed_refund(address _oft, bytes calldata _message, uint256 _amount, address _refundAddress) external {
        _refund(_oft, _message, _amount, _refundAddress);
    }

    /**
     * @notice Expose _lzReceive for testing
     */
    function exposed_lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external {
        _lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    /**
     * @notice Expose _handleUnstake for testing
     */
    function exposed_handleUnstake(
        Origin calldata _origin,
        bytes32 _guid,
        IUnstakeMessenger.UnstakeMessage memory unstakeMsg
    ) external {
        _handleUnstake(_origin, _guid, unstakeMsg);
    }
}
