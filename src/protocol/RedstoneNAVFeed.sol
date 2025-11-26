// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TEMPORARILY COMMENTED OUT - Missing redstone-oracles-monorepo submodule
// import "@redstone-finance/evm-connector/contracts/data-services/MainDemoConsumerBase.sol";
import {IOracle} from "./periphery/IOracle.sol";

// TEMPORARILY COMMENTED OUT - Missing redstone-oracles-monorepo submodule
// contract RedstoneNAVFeed is IOracle, MainDemoConsumerBase {
contract RedstoneNAVFeed is IOracle {
    uint256 private _price;

    // Mock implementation
    function price() external view returns (uint256) {
        // return getOracleNumericValueFromTxMsg(bytes32("NAV")); // Exact Identifier TBD
        return _price;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
