// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title DeploymentRegistry
 * @notice Registry for storing and retrieving deployment addresses
 * @dev Allows modular deployment scripts to share contract addresses
 * @dev Stores addresses per chain ID to prevent overwrites between networks
 */
contract DeploymentRegistry is Script {
    using stdJson for string;

    // Registry path is now dynamic based on chain ID
    // Example: broadcast/deployment-addresses-31337.json (for Anvil)
    //          broadcast/deployment-addresses-11155111.json (for Sepolia)
    function _getRegistryPath() internal view returns (string memory) {
        return string(abi.encodePacked("broadcast/deployment-addresses-", vm.toString(block.chainid), ".json"));
    }

    struct DeploymentAddresses {
        address create2Factory;
        address oracle;
        address dlfToken;
        address itryToken;
        address custodian;
        address bufferPool;
        address staking;
        address yieldDistributor;
        address controller;
        address itryAdapter;
        address shareAdapter;
        address wiTryVaultComposer;
    }

    /**
     * @notice Save deployment addresses to JSON file (chain-specific)
     */
    function saveAddresses(DeploymentAddresses memory addrs) internal {
        string memory registryPath = _getRegistryPath();
        string memory json = "deployment";

        vm.serializeAddress(json, "create2Factory", addrs.create2Factory);
        vm.serializeAddress(json, "oracle", addrs.oracle);
        vm.serializeAddress(json, "dlfToken", addrs.dlfToken);
        vm.serializeAddress(json, "itryToken", addrs.itryToken);
        vm.serializeAddress(json, "custodian", addrs.custodian);
        vm.serializeAddress(json, "bufferPool", addrs.bufferPool);
        vm.serializeAddress(json, "staking", addrs.staking);
        vm.serializeAddress(json, "yieldDistributor", addrs.yieldDistributor);
        vm.serializeAddress(json, "controller", addrs.controller);
        vm.serializeAddress(json, "itryAdapter", addrs.itryAdapter);
        vm.serializeAddress(json, "shareAdapter", addrs.shareAdapter);
        string memory finalJson = vm.serializeAddress(json, "wiTryVaultComposer", addrs.wiTryVaultComposer);

        vm.writeJson(finalJson, registryPath);
        console2.log("Saved deployment addresses to:", registryPath);
        console2.log("Chain ID:", block.chainid);
    }

    /**
     * @notice Load deployment addresses from JSON file (chain-specific)
     */
    function loadAddresses() internal view returns (DeploymentAddresses memory) {
        string memory registryPath = _getRegistryPath();
        string memory json = vm.readFile(registryPath);

        return DeploymentAddresses({
            create2Factory: json.readAddress(".create2Factory"),
            oracle: json.readAddress(".oracle"),
            dlfToken: json.readAddress(".dlfToken"),
            itryToken: json.readAddress(".itryToken"),
            custodian: json.readAddress(".custodian"),
            bufferPool: json.readAddress(".bufferPool"),
            staking: json.readAddress(".staking"),
            yieldDistributor: json.readAddress(".yieldDistributor"),
            controller: json.readAddress(".controller"),
            itryAdapter: json.readAddress(".itryAdapter"),
            shareAdapter: json.readAddress(".shareAdapter"),
            wiTryVaultComposer: json.readAddress(".wiTryVaultComposer")
        });
    }

    /**
     * @notice Check if deployment registry exists (chain-specific)
     */
    function registryExists() internal view returns (bool) {
        string memory registryPath = _getRegistryPath();
        try vm.readFile(registryPath) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Clear deployment registry (chain-specific)
     */
    function clearRegistry() internal {
        string memory registryPath = _getRegistryPath();
        try vm.removeFile(registryPath) {
            console2.log("Cleared deployment registry:", registryPath);
        } catch {
            console2.log("No registry to clear");
        }
    }
}
