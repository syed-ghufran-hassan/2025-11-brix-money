// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CrossChainTestBase} from "./CrossChainTestBase.sol";
import {console} from "forge-std/console.sol";

/**
 * @title CrossChainTestBaseTest
 * @notice Tests for the CrossChainTestBase infrastructure
 * @dev Verifies fork creation, chain switching, and account funding
 */
contract CrossChainTestBaseTest is CrossChainTestBase {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that forks are created successfully
     */
    function test_ForkCreation() public {
        console.log("Testing fork creation...");

        // Verify we're on Sepolia by default
        assertEq(getCurrentChainId(), SEPOLIA_CHAIN_ID, "Should start on Sepolia");
        assertEq(keccak256(bytes(getCurrentChain())), keccak256(bytes("Sepolia")), "Chain name should be Sepolia");

        // Switch to OP Sepolia and verify
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        assertEq(getCurrentChainId(), OP_SEPOLIA_CHAIN_ID, "Should be on OP Sepolia");
        assertEq(keccak256(bytes(getCurrentChain())), keccak256(bytes("OP Sepolia")), "Chain name should be OP Sepolia");

        // Switch back to Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";

        // Back to Sepolia
        assertEq(getCurrentChainId(), SEPOLIA_CHAIN_ID, "Should be back on Sepolia");

        console.log("[PASS] Fork creation test passed");
    }

    /**
     * @notice Test chain switching functionality
     */
    function test_ChainSwitching() public {
        console.log("Testing chain switching...");

        // Test switching to Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        assertCorrectChain(SEPOLIA_CHAIN_ID);
        logChainState();

        // Test switching to OP Sepolia
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        assertCorrectChain(OP_SEPOLIA_CHAIN_ID);
        logChainState();

        // Test using switchToDestination helper
        switchToDestination(SEPOLIA_EID);
        assertEq(getCurrentChainId(), SEPOLIA_CHAIN_ID, "Should switch to Sepolia via EID");

        switchToDestination(OP_SEPOLIA_EID);
        assertEq(getCurrentChainId(), OP_SEPOLIA_CHAIN_ID, "Should switch to OP Sepolia via EID");

        console.log("[PASS] Chain switching test passed");
    }

    /**
     * @notice Test account funding on both chains
     */
    function test_AccountFunding() public {
        console.log("Testing account funding...");

        // Check balances on Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        console.log("Checking Sepolia balances...");
        assertEq(deployer.balance, 100 ether, "Deployer should have 100 ETH on Sepolia");
        assertEq(userL1.balance, 100 ether, "UserL1 should have 100 ETH on Sepolia");
        assertEq(userL2.balance, 100 ether, "UserL2 should have 100 ETH on Sepolia");

        console.log("  Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("  UserL1 balance:", userL1.balance / 1e18, "ETH");
        console.log("  UserL2 balance:", userL2.balance / 1e18, "ETH");

        // Check balances on OP Sepolia
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        console.log("Checking OP Sepolia balances...");
        assertEq(deployer.balance, 100 ether, "Deployer should have 100 ETH on OP Sepolia");
        assertEq(userL1.balance, 100 ether, "UserL1 should have 100 ETH on OP Sepolia");
        assertEq(userL2.balance, 100 ether, "UserL2 should have 100 ETH on OP Sepolia");

        console.log("  Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("  UserL1 balance:", userL1.balance / 1e18, "ETH");
        console.log("  UserL2 balance:", userL2.balance / 1e18, "ETH");

        console.log("[PASS] Account funding test passed");
    }
}
