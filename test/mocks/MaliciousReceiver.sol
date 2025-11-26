// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFastAccessVault} from "../../src/protocol/interfaces/IFastAccessVault.sol";

/**
 * @title MaliciousReceiver
 * @notice Mock contract that rejects ETH and attempts reentrancy
 * @dev Used to test rescueToken failure scenarios
 */
contract MaliciousReceiver {
    bool public shouldReject;
    bool public shouldReenter;
    address public vault;

    function setShouldReject(bool _shouldReject) external {
        shouldReject = _shouldReject;
    }

    function setShouldReenter(bool _shouldReenter) external {
        shouldReenter = _shouldReenter;
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    // Reject ETH when shouldReject is true
    receive() external payable {
        if (shouldReject) {
            revert("Rejecting ETH");
        }

        // Attempt reentrancy if configured
        if (shouldReenter && vault != address(0)) {
            // Try to call rescueToken again (will fail because not owner)
            IFastAccessVault(vault).rebalanceFunds();
        }
    }

    fallback() external payable {
        if (shouldReject) {
            revert("Rejecting ETH");
        }
    }
}
