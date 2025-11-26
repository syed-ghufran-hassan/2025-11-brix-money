// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20FailingTransfer
 * @notice Mock ERC20 that can be configured to return false on transfer (without reverting)
 * @dev Used to test transfer failure handling
 */
contract MockERC20FailingTransfer is ERC20 {
    bool public shouldFail;

    constructor() ERC20("Failing Token", "FAIL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}
