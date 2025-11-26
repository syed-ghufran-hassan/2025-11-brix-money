// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CrossChainTestBase} from "./CrossChainTestBase.sol";
import {console} from "forge-std/Test.sol";
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Step3_DeploymentTest
 * @notice Test contract to verify Step 3 implementation - Contract Deployment
 * @dev Tests deployment of all contracts and peer configuration
 */
contract Step3_DeploymentTest is CrossChainTestBase {
    function setUp() public override {
        super.setUp();
        console.log("\n=== Step 3 Deployment Test Setup ===");
    }

    /**
     * @notice Test deployment of all contracts on both chains
     */
    function test_DeployAllContracts() public {
        console.log("\n=== Testing Contract Deployment ===");

        // Deploy all contracts
        deployAllContracts();

        // Verify all contracts deployed (non-zero addresses)
        assertTrue(address(sepoliaITryToken) != address(0), "Sepolia iTryToken not deployed");
        assertTrue(address(sepoliaAdapter) != address(0), "Sepolia Adapter not deployed");
        assertTrue(address(sepoliaVault) != address(0), "Sepolia Vault not deployed");
        assertTrue(address(sepoliaVaultComposer) != address(0), "Sepolia VaultComposer not deployed");
        assertTrue(address(sepoliaShareAdapter) != address(0), "Sepolia ShareAdapter not deployed");
        assertTrue(address(opSepoliaOFT) != address(0), "OP Sepolia OFT not deployed");
        assertTrue(address(opSepoliaShareOFT) != address(0), "OP Sepolia ShareOFT not deployed");
        assertTrue(address(opSepoliaUnstakeMessenger) != address(0), "OP Sepolia UnstakeMessenger not deployed");

        console.log("-All 8 contracts deployed successfully");
    }

    /**
     * @notice Test that contracts are deployed on correct chains
     */
    function test_ContractsOnCorrectChains() public {
        deployAllContracts();

        // Check Sepolia contracts
        vm.selectFork(sepoliaForkId);
        assertEq(block.chainid, SEPOLIA_CHAIN_ID, "Not on Sepolia");

        // Verify Sepolia contracts exist
        assertTrue(address(sepoliaITryToken).code.length > 0, "iTryToken not on Sepolia");
        assertTrue(address(sepoliaAdapter).code.length > 0, "Adapter not on Sepolia");
        assertTrue(address(sepoliaVault).code.length > 0, "Vault not on Sepolia");
        assertTrue(address(sepoliaVaultComposer).code.length > 0, "VaultComposer not on Sepolia");
        assertTrue(address(sepoliaShareAdapter).code.length > 0, "ShareAdapter not on Sepolia");

        console.log("-Sepolia contracts deployed on correct chain");

        // Check OP Sepolia contracts
        vm.selectFork(opSepoliaForkId);
        assertEq(block.chainid, OP_SEPOLIA_CHAIN_ID, "Not on OP Sepolia");

        // Verify OP Sepolia contracts exist
        assertTrue(address(opSepoliaOFT).code.length > 0, "OFT not on OP Sepolia");
        assertTrue(address(opSepoliaShareOFT).code.length > 0, "ShareOFT not on OP Sepolia");
        assertTrue(address(opSepoliaUnstakeMessenger).code.length > 0, "UnstakeMessenger not on OP Sepolia");

        console.log("-OP Sepolia contracts deployed on correct chain");
    }

    /**
     * @notice Test ownership of deployed contracts
     */
    function test_ContractOwnership() public {
        deployAllContracts();

        // Check Sepolia contract ownership
        vm.selectFork(sepoliaForkId);
        assertEq(Ownable(address(sepoliaITryToken)).owner(), deployer, "iTryToken owner mismatch");
        assertEq(Ownable(address(sepoliaAdapter)).owner(), deployer, "Adapter owner mismatch");
        assertEq(Ownable(address(sepoliaVault)).owner(), deployer, "Vault owner mismatch");
        assertEq(Ownable(address(sepoliaVaultComposer)).owner(), deployer, "VaultComposer owner mismatch");
        assertEq(Ownable(address(sepoliaShareAdapter)).owner(), deployer, "ShareAdapter owner mismatch");

        // Check OP Sepolia contract ownership
        vm.selectFork(opSepoliaForkId);
        assertEq(Ownable(address(opSepoliaOFT)).owner(), deployer, "OFT owner mismatch");
        assertEq(Ownable(address(opSepoliaShareOFT)).owner(), deployer, "ShareOFT owner mismatch");
        assertEq(Ownable(address(opSepoliaUnstakeMessenger)).owner(), deployer, "UnstakeMessenger owner mismatch");

        console.log("-All contracts owned by deployer");
    }

    /**
     * @notice Test endpoint configuration
     */
    function test_EndpointConfiguration() public {
        deployAllContracts();

        // Check Sepolia endpoints
        vm.selectFork(sepoliaForkId);
        assertEq(address(IOAppCore(sepoliaAdapter).endpoint()), SEPOLIA_ENDPOINT, "Sepolia Adapter endpoint mismatch");
        assertEq(
            address(IOAppCore(sepoliaShareAdapter).endpoint()),
            SEPOLIA_ENDPOINT,
            "Sepolia ShareAdapter endpoint mismatch"
        );
        assertEq(
            address(IOAppCore(sepoliaVaultComposer).endpoint()),
            SEPOLIA_ENDPOINT,
            "Sepolia VaultComposer endpoint mismatch"
        );

        // Check OP Sepolia endpoints
        vm.selectFork(opSepoliaForkId);
        assertEq(address(IOAppCore(opSepoliaOFT).endpoint()), OP_SEPOLIA_ENDPOINT, "OP Sepolia OFT endpoint mismatch");
        assertEq(
            address(IOAppCore(opSepoliaShareOFT).endpoint()),
            OP_SEPOLIA_ENDPOINT,
            "OP Sepolia ShareOFT endpoint mismatch"
        );
        assertEq(
            address(IOAppCore(opSepoliaUnstakeMessenger).endpoint()),
            OP_SEPOLIA_ENDPOINT,
            "OP Sepolia UnstakeMessenger endpoint mismatch"
        );

        console.log("-All endpoints configured correctly");
    }

    /**
     * @notice Test peer configuration for iTRY tokens
     */
    function test_ITryPeerConfiguration() public {
        deployAllContracts();

        // Check Sepolia -> OP Sepolia peer
        vm.selectFork(sepoliaForkId);
        bytes32 expectedPeer1 = bytes32(uint256(uint160(address(opSepoliaOFT))));
        bytes32 actualPeer1 = IOAppCore(address(sepoliaAdapter)).peers(OP_SEPOLIA_EID);
        assertEq(actualPeer1, expectedPeer1, "Sepolia adapter peer incorrect");

        // Check OP Sepolia -> Sepolia peer
        vm.selectFork(opSepoliaForkId);
        bytes32 expectedPeer2 = bytes32(uint256(uint160(address(sepoliaAdapter))));
        bytes32 actualPeer2 = IOAppCore(address(opSepoliaOFT)).peers(SEPOLIA_EID);
        assertEq(actualPeer2, expectedPeer2, "OP Sepolia OFT peer incorrect");

        console.log("-iTRY peer configuration verified");
    }

    /**
     * @notice Test peer configuration for wiTRY shares
     */
    function test_SharePeerConfiguration() public {
        deployAllContracts();

        // Check Sepolia -> OP Sepolia peer
        vm.selectFork(sepoliaForkId);
        bytes32 expectedPeer1 = bytes32(uint256(uint160(address(opSepoliaShareOFT))));
        bytes32 actualPeer1 = IOAppCore(address(sepoliaShareAdapter)).peers(OP_SEPOLIA_EID);
        assertEq(actualPeer1, expectedPeer1, "Sepolia share adapter peer incorrect");

        // Check OP Sepolia -> Sepolia peer
        vm.selectFork(opSepoliaForkId);
        bytes32 expectedPeer2 = bytes32(uint256(uint160(address(sepoliaShareAdapter))));
        bytes32 actualPeer2 = IOAppCore(address(opSepoliaShareOFT)).peers(SEPOLIA_EID);
        assertEq(actualPeer2, expectedPeer2, "OP Sepolia share OFT peer incorrect");

        console.log("-wiTRY share peer configuration verified");
    }

    /**
     * @notice Test the verifyPeerConfiguration helper function
     */
    function test_VerifyPeerConfigurationHelper() public {
        deployAllContracts();

        // This should pass without reverting
        verifyPeerConfiguration();

        console.log("-verifyPeerConfiguration() helper works correctly");
    }

    /**
     * @notice Test chain switching works correctly after deployment
     */
    function test_ChainSwitchingAfterDeployment() public {
        deployAllContracts();

        // Start on Sepolia
        switchToDestination(SEPOLIA_EID);
        assertEq(block.chainid, SEPOLIA_CHAIN_ID, "Should be on Sepolia");
        assertEq(getCurrentChain(), "Sepolia", "Chain name mismatch");

        // Switch to OP Sepolia using EID
        switchToDestination(OP_SEPOLIA_EID);
        assertEq(block.chainid, OP_SEPOLIA_CHAIN_ID, "Should be on OP Sepolia");
        assertEq(getCurrentChain(), "OP Sepolia", "Chain name mismatch");

        // Switch back to Sepolia
        switchToDestination(SEPOLIA_EID);
        assertEq(block.chainid, SEPOLIA_CHAIN_ID, "Should be back on Sepolia");
        assertEq(getCurrentChain(), "Sepolia", "Chain name mismatch");

        console.log("-Chain switching works correctly");
    }

    /**
     * @notice Test token minting capability on Sepolia
     */
    function test_MintCapability() public {
        deployAllContracts();

        uint256 mintAmount = 1000 ether;

        // Mint tokens to userL1
        mintITry(userL1, mintAmount);

        // Verify balance
        vm.selectFork(sepoliaForkId);
        uint256 balance = sepoliaITryToken.balanceOf(userL1);
        assertEq(balance, mintAmount, "Mint amount mismatch");

        console.log("-iTRY minting works correctly");
    }

    /**
     * @notice Test all Step 3 success criteria
     */
    function test_Step3_AllSuccessCriteria() public {
        console.log("\n=== Verifying All Step 3 Success Criteria ===");

        // Deploy contracts
        deployAllContracts();

        // Success Criterion 1: All 8 contracts deployed
        assertTrue(address(sepoliaITryToken) != address(0), "SC1: iTryToken missing");
        assertTrue(address(sepoliaAdapter) != address(0), "SC1: Adapter missing");
        assertTrue(address(sepoliaVault) != address(0), "SC1: Vault missing");
        assertTrue(address(sepoliaVaultComposer) != address(0), "SC1: VaultComposer missing");
        assertTrue(address(sepoliaShareAdapter) != address(0), "SC1: ShareAdapter missing");
        assertTrue(address(opSepoliaOFT) != address(0), "SC1: OFT missing");
        assertTrue(address(opSepoliaShareOFT) != address(0), "SC1: ShareOFT missing");
        assertTrue(address(opSepoliaUnstakeMessenger) != address(0), "SC1: UnstakeMessenger missing");
        console.log("-Success Criterion 1: All 8 contracts deployed");

        // Success Criterion 2: All contract addresses are non-zero
        console.log("-Success Criterion 2: All addresses non-zero (verified above)");

        // Success Criterion 3: sepoliaAdapter.peers(OP_SEPOLIA_EID) returns OP Sepolia OFT address
        vm.selectFork(sepoliaForkId);
        bytes32 peer = IOAppCore(address(sepoliaAdapter)).peers(OP_SEPOLIA_EID);
        assertEq(peer, bytes32(uint256(uint160(address(opSepoliaOFT)))), "SC3: Peer mismatch");
        console.log("-Success Criterion 3: Sepolia adapter peer correct");

        // Success Criterion 4: Reverse peer check passes
        vm.selectFork(opSepoliaForkId);
        bytes32 reversePeer = IOAppCore(address(opSepoliaOFT)).peers(SEPOLIA_EID);
        assertEq(reversePeer, bytes32(uint256(uint160(address(sepoliaAdapter)))), "SC4: Reverse peer mismatch");
        console.log("-Success Criterion 4: Reverse peer check passes");

        // Success Criterion 5: Ownership set to deployer
        vm.selectFork(sepoliaForkId);
        assertEq(Ownable(address(sepoliaITryToken)).owner(), deployer, "SC5: Owner mismatch");
        assertEq(Ownable(address(sepoliaAdapter)).owner(), deployer, "SC5: Owner mismatch");
        vm.selectFork(opSepoliaForkId);
        assertEq(Ownable(address(opSepoliaOFT)).owner(), deployer, "SC5: Owner mismatch");
        console.log("-Success Criterion 5: Ownership correct");

        // Success Criterion 6: Endpoints configured correctly
        vm.selectFork(sepoliaForkId);
        assertEq(address(IOAppCore(sepoliaAdapter).endpoint()), SEPOLIA_ENDPOINT, "SC6: Endpoint mismatch");
        vm.selectFork(opSepoliaForkId);
        assertEq(address(IOAppCore(opSepoliaOFT).endpoint()), OP_SEPOLIA_ENDPOINT, "SC6: Endpoint mismatch");
        console.log("-Success Criterion 6: Endpoints configured correctly");

        console.log("\n ALL STEP 3 SUCCESS CRITERIA MET! ");
    }
}
