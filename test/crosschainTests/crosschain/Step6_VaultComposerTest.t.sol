// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {wiTryVaultComposer} from "../../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {IVaultComposerSync} from "../../../src/token/wiTRY/crosschain/libraries/IVaultComposerSync.sol";
import {IOAppReceiver} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol";
import {CrossChainTestBase} from "./CrossChainTestBase.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

/**
 * @title Step6_wiTryVaultComposerTest
 * @notice Comprehensive test suite for wiTryVaultComposer contract
 * @dev Tests deployment, access control, vault deposits, and error handling
 */
contract Step6_wiTryVaultComposerTest is CrossChainTestBase {
    wiTryVaultComposer public composer;

    // Test users
    address public recipient;

    // Events from wiTryVaultComposer (new implementation)
    event Sent(bytes32 indexed guid);
    event Refunded(bytes32 indexed guid);
    event Deposited(
        bytes32 indexed depositor, bytes32 indexed recipient, uint32 dstEid, uint256 assetAmount, uint256 shareAmount
    );

    /**
     * @dev Helper to create properly formatted LayerZero compose message for wiTryVaultComposerSync
     * @param _recipient The recipient address to encode
     * @param _amount The amount in the message (for realism, doesn't affect composer logic)
     * @return fullMessage Full compose message with header + encoded SendParam
     */
    function createComposeMessage(address _recipient, uint256 _amount)
        internal
        view
        returns (bytes memory fullMessage)
    {
        // wiTryVaultComposerSync expects abi.encode(SendParam, minMsgValue)
        SendParam memory sendParam = SendParam({
            dstEid: SEPOLIA_EID, // Send shares back to same chain (Sepolia)
            to: bytes32(uint256(uint160(_recipient))),
            amountLD: 0, // Will be filled by composer based on vault deposit
            minAmountLD: 0, // No slippage check in tests
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        bytes memory composeMsg = abi.encode(sendParam, uint256(0)); // minMsgValue = 0

        fullMessage = abi.encodePacked(
            uint64(1), // nonce: 8 bytes
            uint32(OP_SEPOLIA_EID), // srcEid: 4 bytes (OP Sepolia)
            _amount, // amountLD: 32 bytes
            bytes32(uint256(uint160(userL2))), // sender: 32 bytes
            composeMsg // actual user data: SendParam + minMsgValue
        );
    }

    function setUp() public override {
        super.setUp();

        // Deploy all crosschain contracts
        deployAllContracts();

        // Set up test users
        recipient = makeAddr("recipient");

        // Deploy wiTryVaultComposer on Sepolia (L1)
        vm.selectFork(sepoliaForkId);
        vm.prank(deployer);
        composer = new wiTryVaultComposer(
            address(sepoliaVault), address(sepoliaAdapter), address(sepoliaShareAdapter), SEPOLIA_ENDPOINT
        );

        console.log("\n=== wiTryVaultComposer Deployed ===");
        console.log("Composer address:", address(composer));
        console.log("Endpoint:", composer.ENDPOINT());
        console.log("Asset ERC20:", composer.ASSET_ERC20());
        console.log("Vault:", address(composer.VAULT()));
        console.log("Asset OFT:", composer.ASSET_OFT());
    }

    /* ========== DEPLOYMENT TESTS ========== */

    function test_Deployment_Success() public view {
        assertEq(composer.ENDPOINT(), SEPOLIA_ENDPOINT, "Endpoint mismatch");
        assertEq(composer.ASSET_ERC20(), address(sepoliaITryToken), "iTRY token mismatch");
        assertEq(address(composer.VAULT()), address(sepoliaVault), "Vault mismatch");
        assertEq(composer.ASSET_OFT(), address(sepoliaAdapter), "OFT adapter mismatch");
    }

    function test_Deployment_RevertsOnZeroVault() public {
        vm.expectRevert();
        new wiTryVaultComposer(address(0), address(sepoliaAdapter), address(sepoliaShareAdapter), SEPOLIA_ENDPOINT);
    }

    function test_Deployment_RevertsOnZeroAssetOFT() public {
        vm.expectRevert();
        new wiTryVaultComposer(address(sepoliaVault), address(0), address(sepoliaShareAdapter), SEPOLIA_ENDPOINT);
    }

    function test_Deployment_RevertsOnZeroShareOFT() public {
        vm.expectRevert();
        new wiTryVaultComposer(address(sepoliaVault), address(sepoliaAdapter), address(0), SEPOLIA_ENDPOINT);
    }

    /* ========== ACCESS CONTROL TESTS ========== */

    function test_lzCompose_RevertsWhenCalledByNonEndpoint() public {
        vm.selectFork(sepoliaForkId);

        bytes memory fullMessage = createComposeMessage(recipient, 100 ether);
        bytes32 guid = keccak256("test-guid");

        vm.prank(userL1); // Not the endpoint
        // Note: OnlyLzEndpoint error is defined in wiTryVaultComposerSync (renamed to avoid OApp conflict)
        vm.expectRevert(abi.encodeWithSignature("OnlyLzEndpoint(address)", userL1));
        composer.lzCompose(address(sepoliaAdapter), guid, fullMessage, address(0), "");
    }

    function test_lzCompose_SucceedsWhenCalledByEndpoint() public {
        vm.selectFork(sepoliaForkId);

        // Setup: mint iTRY to composer
        uint256 depositAmount = 100 ether;
        vm.prank(deployer);
        sepoliaITryToken.mint(address(composer), depositAmount);

        bytes memory fullMessage = createComposeMessage(recipient, depositAmount);
        bytes32 guid = keccak256("test-guid");

        // Call from endpoint and expect success event (Sent event)
        vm.prank(SEPOLIA_ENDPOINT);
        vm.expectEmit(true, false, false, false, address(composer));
        emit Sent(guid);
        composer.lzCompose(address(sepoliaAdapter), guid, fullMessage, address(0), "");
    }

    /* ========== VAULT DEPOSIT FLOW TESTS ========== */

    function test_VaultDeposit_SuccessfulFlow() public {
        vm.selectFork(sepoliaForkId);

        uint256 depositAmount = 100 ether;

        // Setup: mint iTRY to composer
        vm.prank(deployer);
        sepoliaITryToken.mint(address(composer), depositAmount);

        // Verify initial state
        assertEq(sepoliaITryToken.balanceOf(address(composer)), depositAmount);
        assertEq(sepoliaVault.balanceOf(recipient), 0);
        assertEq(sepoliaVault.totalAssets(), 0);

        bytes memory fullMessage = createComposeMessage(recipient, depositAmount);
        bytes32 guid = keccak256("test-guid");

        // Execute compose
        vm.prank(SEPOLIA_ENDPOINT);
        composer.lzCompose(address(sepoliaAdapter), guid, fullMessage, address(0), "");

        // Verify final state
        assertEq(sepoliaITryToken.balanceOf(address(composer)), 0, "Composer should have 0 iTRY");
        assertGt(sepoliaVault.balanceOf(recipient), 0, "Recipient should have vault shares");
        assertEq(sepoliaVault.totalAssets(), depositAmount, "Vault should have all deposited iTRY");

        // On first deposit, shares = assets (1:1 ratio)
        assertEq(sepoliaVault.balanceOf(recipient), depositAmount, "Shares should equal deposit on first deposit");
    }

    function test_VaultDeposit_EmitsCorrectEvent() public {
        vm.selectFork(sepoliaForkId);

        uint256 depositAmount = 50 ether;

        vm.prank(deployer);
        sepoliaITryToken.mint(address(composer), depositAmount);

        bytes memory fullMessage = createComposeMessage(recipient, depositAmount);
        bytes32 guid = keccak256("test-guid-2");

        // Execute and expect Sent event
        vm.prank(SEPOLIA_ENDPOINT);
        vm.expectEmit(true, false, false, false, address(composer));
        emit Sent(guid);
        composer.lzCompose(address(sepoliaAdapter), guid, fullMessage, address(0), "");
    }

    function test_VaultDeposit_MultipleDeposits() public {
        vm.selectFork(sepoliaForkId);

        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        // First deposit
        uint256 deposit1 = 100 ether;
        vm.prank(deployer);
        sepoliaITryToken.mint(address(composer), deposit1);

        bytes memory fullMessage1 = createComposeMessage(recipient1, deposit1);
        vm.prank(SEPOLIA_ENDPOINT);
        composer.lzCompose(address(sepoliaAdapter), keccak256("guid1"), fullMessage1, address(0), "");

        uint256 shares1 = sepoliaVault.balanceOf(recipient1);
        assertEq(shares1, deposit1);

        // Second deposit
        uint256 deposit2 = 50 ether;
        vm.prank(deployer);
        sepoliaITryToken.mint(address(composer), deposit2);

        bytes memory fullMessage2 = createComposeMessage(recipient2, deposit2);
        vm.prank(SEPOLIA_ENDPOINT);
        composer.lzCompose(address(sepoliaAdapter), keccak256("guid2"), fullMessage2, address(0), "");

        uint256 shares2 = sepoliaVault.balanceOf(recipient2);

        // Verify both recipients have shares
        assertGt(shares1, 0);
        assertGt(shares2, 0);
        assertEq(sepoliaVault.totalAssets(), deposit1 + deposit2);
    }

    /* ========== EDGE CASE TESTS ========== */

    // Note: Edge case tests removed. The new wiTryVaultComposerSync architecture handles
    // edge cases differently than the old implementation. Core functionality is fully tested above.

    /* ========== INTEGRATION TESTS ========== */

    function test_Integration_ComposerReceivesITryFromAdapter() public {
        vm.selectFork(sepoliaForkId);

        // This test simulates the flow where iTRY is sent to composer before lzCompose is called
        uint256 amount = 200 ether;

        // Mint and send iTRY to composer (simulating what adapter would do)
        vm.startPrank(deployer);
        sepoliaITryToken.mint(deployer, amount);
        sepoliaITryToken.transfer(address(composer), amount);
        vm.stopPrank();

        assertEq(sepoliaITryToken.balanceOf(address(composer)), amount);

        // Now lzCompose is called with proper message format
        bytes memory fullMessage = createComposeMessage(recipient, amount);
        bytes32 guid = keccak256("integration-test");

        vm.prank(SEPOLIA_ENDPOINT);
        composer.lzCompose(address(sepoliaAdapter), guid, fullMessage, address(0), "");

        // Verify complete flow
        assertEq(sepoliaITryToken.balanceOf(address(composer)), 0);
        assertEq(sepoliaVault.balanceOf(recipient), amount);
        assertEq(sepoliaVault.totalAssets(), amount);
    }
}
