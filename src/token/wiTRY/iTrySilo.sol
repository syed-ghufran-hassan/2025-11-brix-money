// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IiTrySiloDefinitions} from "./interfaces/IiTrySiloDefinitions.sol";

/**
 * @title iTrySilo
 * @notice The Silo allows to store iTry during the stake cooldown process.
 */
contract iTrySilo is IiTrySiloDefinitions {
    using SafeERC20 for IERC20;

    address immutable STAKING_VAULT;
    IERC20 immutable iTry;

    constructor(address _stakingVault, address _iTryToken) {
        STAKING_VAULT = _stakingVault;
        iTry = IERC20(_iTryToken);
    }

    modifier onlyStakingVault() {
        if (msg.sender != STAKING_VAULT) revert OnlyStakingVault();
        _;
    }

    function withdraw(address to, uint256 amount) external onlyStakingVault {
        iTry.transfer(to, amount);
    }
}
