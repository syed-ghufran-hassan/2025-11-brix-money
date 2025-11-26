// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SendParam, MessagingFee, MessagingReceipt, OFTReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockOFT
 * @notice Minimal mock for OFT (Omnichain Fungible Token) used in wiTryVaultComposer unit tests
 * @dev Simulates OFT behavior with fixed return values
 *      No actual token transfers or LayerZero integration - just returns mock data
 */
contract MockOFT {
    address public immutable token;
    address public immutable endpoint;
    uint256 public fixedNativeFee = 1 ether; // Default fixed fee

    constructor(address _token, address _endpoint) {
        token = _token;
        endpoint = _endpoint;
    }

    /**
     * @notice Mock quoteSend - returns fixed messaging fee
     * @param _sendParam Send parameters (unused in mock)
     * @param _payInLzToken Whether to pay in LZ token (unused in mock)
     * @return msgFee Fixed messaging fee
     */
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory msgFee)
    {
        return MessagingFee(fixedNativeFee, 0);
    }

    /**
     * @notice Mock send - transfers tokens from caller and returns mock receipts
     * @param _sendParam Send parameters (used to get amount to transfer)
     * @param _fee Messaging fee (unused in mock)
     * @param _refundAddress Refund address (unused in mock)
     * @return msgReceipt Mock messaging receipt
     * @return oftReceipt Mock OFT receipt
     */
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        // Transfer tokens from caller to this contract (simulates OFT behavior)
        if (_sendParam.amountLD > 0) {
            require(IERC20(token).transferFrom(msg.sender, address(this), _sendParam.amountLD), "Transfer failed");
        }

        msgReceipt = MessagingReceipt(bytes32(uint256(1)), uint64(1), MessagingFee(0, 0));
        oftReceipt = OFTReceipt(_sendParam.amountLD, _sendParam.amountLD);

        return (msgReceipt, oftReceipt);
    }

    /**
     * @notice Mock approvalRequired - returns true (simulates adapter mode)
     */
    function approvalRequired() external pure returns (bool) {
        return true;
    }

    /**
     * @notice Configure the native fee returned by quoteSend
     * @param _fee New fee amount
     */
    function setFixedNativeFee(uint256 _fee) external {
        fixedNativeFee = _fee;
    }
}
