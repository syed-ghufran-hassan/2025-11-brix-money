// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MaliciousReceiver} from "./MaliciousReceiver.sol";
import {MockERC20FailingTransfer} from "./MockERC20FailingTransfer.sol";

/**
 * @title SecurityMocks
 * @notice Provides compatible names for PR #20 test files
 * @dev This file re-exports existing iTry-contracts mocks with the names expected by PR #20 tests:
 *      - RejectEthReceiver: Uses MaliciousReceiver (more feature-rich)
 *      - MockFailingToken: Uses MockERC20FailingTransfer (same functionality)
 */

/**
 * @title RejectEthReceiver
 * @notice Contract that rejects ETH transfers
 * @dev Alias for MaliciousReceiver configured to reject ETH
 *      MaliciousReceiver provides additional reentrancy testing capabilities
 */
contract RejectEthReceiver {
    receive() external payable {
        revert("No ETH accepted");
    }
}

/**
 * @title MockFailingToken
 * @notice Token that can be configured to fail transfers
 * @dev Type alias for MockERC20FailingTransfer
 *      Provides the exact same functionality under the name expected by PR #20 tests
 */
contract MockFailingToken is MockERC20FailingTransfer {}
