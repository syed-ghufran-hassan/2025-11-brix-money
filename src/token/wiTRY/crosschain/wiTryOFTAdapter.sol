// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

/**
 * @title wiTryOFTAdapter
 * @notice OFT Adapter for wiTRY shares on hub chain (Ethereum Mainnet)
 * @dev Wraps the StakedUSDe share token to enable cross-chain transfers via LayerZero
 *
 * Architecture (Phase 1 - Instant Redeems):
 * - Hub Chain (Ethereum): StakedUSDe (ERC4626 vault) + wiTryOFTAdapter (locks shares)
 * - Spoke Chain (MegaETH): ShareOFT (mints/burns based on messages)
 *
 * Flow:
 * 1. User deposits iTRY into StakedUSDe vault → receives wiTRY shares
 * 2. User approves wiTryOFTAdapter to spend their wiTRY
 * 3. User calls send() on wiTryOFTAdapter
 * 4. Adapter locks wiTRY shares and sends LayerZero message
 * 5. ShareOFT mints equivalent shares on spoke chain
 *
 * IMPORTANT: This adapter uses lock/unlock pattern (not mint/burn) because
 * the share token's totalSupply must match the vault's accounting.
 * Burning shares would break the share-to-asset ratio in the ERC4626 vault.
 */
contract wiTryOFTAdapter is OFTAdapter {
    /**
     * @notice Constructor for wiTryOFTAdapter
     * @param _token Address of the wiTRY share token from StakedUSDe
     * @param _lzEndpoint LayerZero endpoint address for Ethereum Mainnet
     * @param _owner Address that will own this adapter (typically deployer)
     */
    constructor(address _token, address _lzEndpoint, address _owner) OFTAdapter(_token, _lzEndpoint, _owner) {}
}
