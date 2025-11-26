// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

/**
 * @title iTryTokenAdapter
 * @notice OFT Adapter for existing iTRY token on hub chain (Ethereum Mainnet)
 * @dev Wraps the existing iTryToken to enable cross-chain transfers via LayerZero
 *
 * Architecture:
 * - Hub Chain (Ethereum): iTryToken (native) + iTryTokenAdapter (locks tokens)
 * - Spoke Chain (MegaETH): iTryTokenOFT (mints/burns based on messages)
 *
 * Flow:
 * 1. User approves iTryTokenAdapter to spend their iTRY
 * 2. User calls send() on iTryTokenAdapter
 * 3. Adapter locks iTRY and sends LayerZero message to spoke chain
 * 4. iTryTokenOFT mints equivalent amount on spoke chain
 */
contract iTryTokenOFTAdapter is OFTAdapter {
    /**
     * @notice Constructor for iTryTokenAdapter
     * @param _token Address of the existing iTryToken contract
     * @param _lzEndpoint LayerZero endpoint address for Ethereum Mainnet
     * @param _owner Address that will own this adapter (typically deployer)
     */
    constructor(address _token, address _lzEndpoint, address _owner) OFTAdapter(_token, _lzEndpoint, _owner) {}
}
