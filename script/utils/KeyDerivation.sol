// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";

/**
 * @title KeyDerivation
 * @notice Helper library for deriving actor keys from a master deployer key
 * @dev Used for testnet deployments to generate deterministic actor addresses
 *
 * Security Model:
 * - Local Anvil (chainId 31337): Uses hardcoded Anvil test keys
 * - Real networks (Sepolia, OP Sepolia, etc.): Derives all keys from DEPLOYER_PRIVATE_KEY
 *
 * Key Derivation:
 *   actorKey = uint256(keccak256(abi.encodePacked(masterKey, actorName)))
 *
 * Benefits:
 * - Only ONE secret to manage (DEPLOYER_PRIVATE_KEY)
 * - Reproducible - same master key = same addresses every time
 * - Secure - derived keys are cryptographically independent
 * - Never uses Anvil defaults on real networks
 */
library KeyDerivation {
    // Anvil default keys (chainId 31337 only)
    uint256 internal constant ANVIL_DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 internal constant ANVIL_TREASURY_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 internal constant ANVIL_CEX_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 internal constant ANVIL_DEX_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    uint256 internal constant ANVIL_STAKER1_KEY = 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a;
    uint256 internal constant ANVIL_STAKER2_KEY = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba;
    uint256 internal constant ANVIL_STAKER3_KEY = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e;
    uint256 internal constant ANVIL_MINTER_KEY = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356;
    uint256 internal constant ANVIL_REDEEMER_KEY = 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97;

    // Actor name constants for derivation
    string internal constant TREASURY_NAME = "TREASURY";
    string internal constant CEX_NAME = "CEX";
    string internal constant DEX_NAME = "DEX";
    string internal constant STAKER1_NAME = "STAKER1";
    string internal constant STAKER2_NAME = "STAKER2";
    string internal constant STAKER3_NAME = "STAKER3";
    string internal constant MINTER_NAME = "MINTER";
    string internal constant REDEEMER_NAME = "REDEEMER";
    string internal constant CUSTODIAN_NAME = "CUSTODIAN";

    struct ActorKeys {
        uint256 deployer;
        uint256 treasury;
        uint256 cex;
        uint256 dex;
        uint256 staker1;
        uint256 staker2;
        uint256 staker3;
        uint256 minter;
        uint256 redeemer;
        uint256 custodian;
    }

    /**
     * @notice Derive a private key from master key and actor name
     * @param masterKey The deployer's master private key
     * @param actorName Unique identifier for the actor
     * @return Derived private key for the actor
     */
    function deriveKey(uint256 masterKey, string memory actorName) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(masterKey, actorName)));
    }

    /**
     * @notice Get all actor keys based on network
     * @param vm Foundry VM for chain detection
     * @param deployerKey The deployer's private key (used on real networks)
     * @return keys ActorKeys struct with all private keys
     */
    function getActorKeys(Vm vm, uint256 deployerKey) internal view returns (ActorKeys memory keys) {
        uint256 chainId = block.chainid;

        // Use Anvil defaults on local network
        if (chainId == 31337) {
            return ActorKeys({
                deployer: ANVIL_DEPLOYER_KEY,
                treasury: ANVIL_TREASURY_KEY,
                cex: ANVIL_CEX_KEY,
                dex: ANVIL_DEX_KEY,
                staker1: ANVIL_STAKER1_KEY,
                staker2: ANVIL_STAKER2_KEY,
                staker3: ANVIL_STAKER3_KEY,
                minter: ANVIL_MINTER_KEY,
                redeemer: ANVIL_REDEEMER_KEY,
                custodian: ANVIL_REDEEMER_KEY // Reuse redeemer key for custodian on Anvil
            });
        }

        // Derive keys from master on real networks
        return ActorKeys({
            deployer: deployerKey,
            treasury: deriveKey(deployerKey, TREASURY_NAME),
            cex: deriveKey(deployerKey, CEX_NAME),
            dex: deriveKey(deployerKey, DEX_NAME),
            staker1: deriveKey(deployerKey, STAKER1_NAME),
            staker2: deriveKey(deployerKey, STAKER2_NAME),
            staker3: deriveKey(deployerKey, STAKER3_NAME),
            minter: deriveKey(deployerKey, MINTER_NAME),
            redeemer: deriveKey(deployerKey, REDEEMER_NAME),
            custodian: deriveKey(deployerKey, CUSTODIAN_NAME)
        });
    }

    /**
     * @notice Convert private key to address
     * @param vm Foundry VM for key->address conversion
     * @param privateKey The private key
     * @return The corresponding Ethereum address
     */
    function keyToAddress(Vm vm, uint256 privateKey) internal pure returns (address) {
        return vm.addr(privateKey);
    }

    /**
     * @notice Get all actor addresses from keys
     * @param vm Foundry VM
     * @param keys ActorKeys struct
     * @return deployer The deployer address
     * @return treasury The treasury address
     * @return cex The CEX address
     * @return dex The DEX address
     * @return staker1 The first staker address
     * @return staker2 The second staker address
     * @return staker3 The third staker address
     * @return minter The minter address
     * @return redeemer The redeemer address
     * @return custodian The custodian address
     */
    function getActorAddresses(Vm vm, ActorKeys memory keys)
        internal
        pure
        returns (
            address deployer,
            address treasury,
            address cex,
            address dex,
            address staker1,
            address staker2,
            address staker3,
            address minter,
            address redeemer,
            address custodian
        )
    {
        deployer = keyToAddress(vm, keys.deployer);
        treasury = keyToAddress(vm, keys.treasury);
        cex = keyToAddress(vm, keys.cex);
        dex = keyToAddress(vm, keys.dex);
        staker1 = keyToAddress(vm, keys.staker1);
        staker2 = keyToAddress(vm, keys.staker2);
        staker3 = keyToAddress(vm, keys.staker3);
        minter = keyToAddress(vm, keys.minter);
        redeemer = keyToAddress(vm, keys.redeemer);
        custodian = keyToAddress(vm, keys.custodian);
    }

    /**
     * @notice Log actor addresses for funding purposes
     * @param vm Foundry VM
     * @param keys ActorKeys struct
     */
    function logActorAddresses(Vm vm, ActorKeys memory keys) internal {
        (
            address deployer,
            address treasury,
            address cex,
            address dex,
            address staker1,
            address staker2,
            address staker3,
            address minter,
            address redeemer,
            address custodian
        ) = getActorAddresses(vm, keys);

        vm.writeLine("stdout", "=========================================");

        if (block.chainid == 31337) {
            vm.writeLine("stdout", "USING ANVIL DEFAULT KEYS (Local Network)");
            vm.writeLine("stdout", "All addresses use hardcoded Anvil test keys");
        } else {
            vm.writeLine("stdout", "USING DERIVED KEYS (Real Network)");
            vm.writeLine("stdout", "All actor keys derived from DEPLOYER_PRIVATE_KEY");
        }

        vm.writeLine("stdout", "=========================================");
        vm.writeLine("stdout", string(abi.encodePacked("Deployer Address:  ", addressToString(deployer))));
        vm.writeLine("stdout", string(abi.encodePacked("Treasury Address:  ", addressToString(treasury))));
        vm.writeLine("stdout", string(abi.encodePacked("CEX Address:       ", addressToString(cex))));
        vm.writeLine("stdout", string(abi.encodePacked("DEX Address:       ", addressToString(dex))));
        vm.writeLine("stdout", string(abi.encodePacked("Staker1 Address:   ", addressToString(staker1))));
        vm.writeLine("stdout", string(abi.encodePacked("Staker2 Address:   ", addressToString(staker2))));
        vm.writeLine("stdout", string(abi.encodePacked("Staker3 Address:   ", addressToString(staker3))));
        vm.writeLine("stdout", string(abi.encodePacked("Minter Address:    ", addressToString(minter))));
        vm.writeLine("stdout", string(abi.encodePacked("Redeemer Address:  ", addressToString(redeemer))));
        vm.writeLine("stdout", string(abi.encodePacked("Custodian Address: ", addressToString(custodian))));
        vm.writeLine("stdout", "=========================================");

        if (block.chainid != 31337) {
            vm.writeLine("stdout", "");
            vm.writeLine("stdout", "IMPORTANT: Fund all addresses with testnet ETH before deployment!");
            vm.writeLine("stdout", "- Deployer: ~0.5 ETH (for contract deployment)");
            vm.writeLine("stdout", "- Each actor: ~0.01 ETH (for setup transactions)");
            vm.writeLine("stdout", "");
        }
    }

    /**
     * @notice Convert address to string
     * @param addr Address to convert
     * @return String representation of address
     */
    function addressToString(address addr) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory data = abi.encodePacked(addr);
        bytes memory str = new bytes(2 + data.length * 2);

        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }
}
