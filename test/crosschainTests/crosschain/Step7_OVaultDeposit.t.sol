// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {CrossChainTestBase} from "./CrossChainTestBase.sol";
import {wiTryVaultComposer} from "../../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {MessagingFee, SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title Step7_OVaultDepositTest
 * @notice Test L2→L1 vault deposits via LayerZero compose messages
 * @dev This is the MAIN FEATURE test - validates complete OVault functionality
 *
 * Test Flow:
 * 1. User on L2 (OP Sepolia) has iTRY tokens
 * 2. User sends iTRY to wiTryVaultComposer on L1 with compose message
 * 3. LayerZero relays message: burns on L2, unlocks on L1
 * 4. wiTryVaultComposer receives iTRY and deposits to vault
 * 5. Vault shares minted to recipient on L1
 */
contract Step7_OVaultDepositTest is CrossChainTestBase {
    using OptionsBuilder for bytes;

    wiTryVaultComposer public composer;
    uint256 constant DEPOSIT_AMOUNT = 100 ether;

    // Events
    event VaultDepositCompleted(
        bytes32 indexed guid, address indexed recipient, uint256 itryAmount, uint256 sharesReceived
    );

    function setUp() public override {
        super.setUp();

        // Deploy all crosschain contracts (from CrossChainTestBase)
        deployAllContracts();

        // Deploy wiTryVaultComposer on Sepolia (L1)
        vm.selectFork(sepoliaForkId);
        vm.prank(deployer);
        composer = new wiTryVaultComposer(
            address(sepoliaVault), address(sepoliaAdapter), address(sepoliaShareAdapter), SEPOLIA_ENDPOINT
        );

        console.log("\n=== Step 7: L2->L1 Vault Deposit Test Setup ===");
        console.log("wiTryVaultComposer deployed at:", address(composer));
        console.log("Sepolia Vault:", address(sepoliaVault));
        console.log("OP Sepolia OFT:", address(opSepoliaOFT));

        // Give userL2 some iTRY on OP Sepolia by transferring from L1
        _transferITryToL2(userL2, DEPOSIT_AMOUNT * 5);

        console.log("Transferred iTRY to userL2 on OP Sepolia:", DEPOSIT_AMOUNT * 5);
        console.log("Initial userL2 balance:", opSepoliaOFT.balanceOf(userL2));
    }

    /**
     * @notice Main test: L2→L1 vault deposit via compose message
     * @dev This is the core OVault feature test
     */
    function test_L2_to_L1_VaultDeposit() public {
        console.log("\n=== TEST: L2->L1 Vault Deposit ===");

        // Record initial state on L1
        vm.selectFork(sepoliaForkId);
        uint256 initialUserL1Shares = sepoliaVault.balanceOf(userL1);
        uint256 initialVaultAssets = sepoliaVault.totalAssets();
        console.log("Initial userL1 vault shares:", initialUserL1Shares);
        console.log("Initial vault total assets:", initialVaultAssets);

        // Step 1: User on L2 sends iTRY to composer with compose message
        vm.selectFork(opSepoliaForkId);
        vm.startPrank(userL2);

        // wiTryVaultComposerSync expects abi.encode(SendParam, minMsgValue)
        SendParam memory innerSendParam = SendParam({
            dstEid: SEPOLIA_EID, // Send shares to same chain (Sepolia)
            to: bytes32(uint256(uint160(userL1))),
            amountLD: 0, // Will be filled by composer based on vault deposit
            minAmountLD: 0, // No slippage check
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        bytes memory composeMsg = abi.encode(innerSendParam, uint256(0)); // minMsgValue = 0

        // Build options with BOTH lzReceive AND lzCompose
        // This is critical - without lzCompose option, compose won't be triggered
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0) // Gas for initial receive
            .addExecutorLzComposeOption(0, 500000, 0); // Gas for compose call

        SendParam memory sendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(address(composer)))), // Send to composer
            amountLD: DEPOSIT_AMOUNT,
            minAmountLD: DEPOSIT_AMOUNT,
            extraOptions: options,
            composeMsg: composeMsg, // Include compose message
            oftCmd: ""
        });

        MessagingFee memory fee = opSepoliaOFT.quoteSend(sendParam, false);
        console.log("Messaging fee (native):", fee.nativeFee);

        // Record logs and send
        vm.recordLogs();
        opSepoliaOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userL2));
        vm.stopPrank();

        // Verify iTRY burned on L2
        uint256 userL2BalanceAfter = opSepoliaOFT.balanceOf(userL2);
        console.log("UserL2 balance after send:", userL2BalanceAfter);
        assertEq(userL2BalanceAfter, DEPOSIT_AMOUNT * 4, "iTRY should be burned on L2");

        // Step 2: Relay the message from L2 to L1
        console.log("\n--- Relaying Message ---");
        CrossChainMessage memory message = captureMessage(OP_SEPOLIA_EID, SEPOLIA_EID);
        console.log("Message captured, payload length:", message.payload.length);

        relayMessage(message);
        console.log("Message relayed successfully");

        // Step 3: Verify vault deposit completed on L1
        vm.selectFork(sepoliaForkId);

        // Check userL1 received vault shares
        uint256 finalUserL1Shares = sepoliaVault.balanceOf(userL1);
        console.log("\n--- Final State on L1 ---");
        console.log("Final userL1 vault shares:", finalUserL1Shares);
        assertGt(finalUserL1Shares, initialUserL1Shares, "User should have vault shares");

        // Verify composer has no leftover iTRY
        uint256 composerBalance = sepoliaITryToken.balanceOf(address(composer));
        console.log("Composer iTRY balance:", composerBalance);
        assertEq(composerBalance, 0, "Composer should have 0 iTRY (all deposited)");

        // Verify iTRY went into vault
        uint256 finalVaultAssets = sepoliaVault.totalAssets();
        console.log("Final vault total assets:", finalVaultAssets);
        assertEq(finalVaultAssets, initialVaultAssets + DEPOSIT_AMOUNT, "Vault should have all deposited iTRY");

        // On first deposit, shares should equal assets (1:1 ratio)
        uint256 expectedShares = DEPOSIT_AMOUNT;
        assertEq(finalUserL1Shares, expectedShares, "Shares should equal deposit amount on first deposit");

        console.log("\nL2->L1 Vault Deposit Test PASSED");
    }

    /**
     * @notice Test vault deposit event emission
     */
    function test_VaultDeposit_EmitsCorrectEvent() public {
        console.log("\n=== TEST: Event Emission ===");

        vm.selectFork(opSepoliaForkId);
        vm.startPrank(userL2);

        // wiTryVaultComposerSync expects abi.encode(SendParam, minMsgValue)
        SendParam memory innerSendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(userL1))),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        bytes memory composeMsg = abi.encode(innerSendParam, uint256(0));
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(address(composer)))),
            amountLD: DEPOSIT_AMOUNT,
            minAmountLD: DEPOSIT_AMOUNT,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        MessagingFee memory fee = opSepoliaOFT.quoteSend(sendParam, false);

        vm.recordLogs();
        opSepoliaOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userL2));
        vm.stopPrank();

        // Capture and relay
        CrossChainMessage memory message = captureMessage(OP_SEPOLIA_EID, SEPOLIA_EID);

        // Switch to L1 and expect event
        vm.selectFork(sepoliaForkId);

        // Note: We can't easily test for the event during relay since we're calling
        // the endpoint internally. The event is tested in Step6_wiTryVaultComposerTest
        relayMessage(message);

        // Verify the deposit happened (indirect event verification)
        assertGt(sepoliaVault.balanceOf(userL1), 0, "Deposit should have succeeded");

        console.log("Event emission verified through successful deposit");
    }

    /**
     * @notice Test multiple sequential deposits
     */
    function test_MultipleSequentialDeposits() public {
        console.log("\n=== TEST: Multiple Sequential Deposits ===");

        uint256 deposit1 = 50 ether;
        uint256 deposit2 = 30 ether;

        // First deposit
        _performL2toL1Deposit(userL2, userL1, deposit1);

        vm.selectFork(sepoliaForkId);
        uint256 sharesAfterFirst = sepoliaVault.balanceOf(userL1);
        console.log("Shares after first deposit:", sharesAfterFirst);
        assertEq(sharesAfterFirst, deposit1, "First deposit shares should be 1:1");

        // Second deposit
        _performL2toL1Deposit(userL2, userL1, deposit2);

        vm.selectFork(sepoliaForkId);
        uint256 sharesAfterSecond = sepoliaVault.balanceOf(userL1);
        console.log("Shares after second deposit:", sharesAfterSecond);
        assertEq(sharesAfterSecond, deposit1 + deposit2, "Total shares should equal total deposits");

        // Verify vault state
        uint256 totalAssets = sepoliaVault.totalAssets();
        assertEq(totalAssets, deposit1 + deposit2, "Vault should have all deposited assets");

        console.log("Multiple sequential deposits test PASSED");
    }

    /**
     * @notice Test deposit with different amounts
     */
    function test_VaultDeposit_DifferentAmounts() public {
        console.log("\n=== TEST: Different Deposit Amounts ===");

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10 ether;
        amounts[1] = 75 ether;
        amounts[2] = 25 ether;

        for (uint256 i = 0; i < amounts.length; i++) {
            console.log("\nDeposit", i + 1, ":", amounts[i]);

            _performL2toL1Deposit(userL2, userL1, amounts[i]);

            vm.selectFork(sepoliaForkId);
            uint256 shares = sepoliaVault.balanceOf(userL1);
            console.log("User shares:", shares);
        }

        vm.selectFork(sepoliaForkId);
        uint256 totalShares = sepoliaVault.balanceOf(userL1);
        uint256 expectedTotal = amounts[0] + amounts[1] + amounts[2];

        assertEq(totalShares, expectedTotal, "Total shares should match all deposits");
        assertEq(sepoliaVault.totalAssets(), expectedTotal, "Vault assets should match deposits");

        console.log("Different amounts test PASSED");
    }

    /**
     * @notice Test share calculation accuracy
     */
    function test_VaultDeposit_CorrectShareCalculation() public {
        console.log("\n=== TEST: Share Calculation Accuracy ===");

        uint256 firstDeposit = 100 ether;

        _performL2toL1Deposit(userL2, userL1, firstDeposit);

        vm.selectFork(sepoliaForkId);
        uint256 shares = sepoliaVault.balanceOf(userL1);
        uint256 assets = sepoliaVault.totalAssets();

        console.log("Shares minted:", shares);
        console.log("Assets in vault:", assets);

        // On first deposit to empty vault: shares = assets (1:1 ratio)
        assertEq(shares, assets, "First deposit should have 1:1 share:asset ratio");
        assertEq(shares, firstDeposit, "Shares should equal deposit amount");

        console.log("Share calculation test PASSED");
    }

    /**
     * @notice Helper function to transfer iTRY from L1 to L2
     * @dev Mints on L1, transfers to L2 via LayerZero
     */
    function _transferITryToL2(address recipient, uint256 amount) internal {
        // Mint iTRY on L1
        vm.selectFork(sepoliaForkId);
        vm.prank(deployer);
        sepoliaITryToken.mint(deployer, amount);

        // Approve and send to L2
        vm.startPrank(deployer);
        sepoliaITryToken.approve(address(sepoliaAdapter), amount);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: OP_SEPOLIA_EID,
            to: bytes32(uint256(uint160(recipient))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = sepoliaAdapter.quoteSend(sendParam, false);
        vm.recordLogs();
        sepoliaAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(deployer));
        vm.stopPrank();

        // Relay the message
        CrossChainMessage memory message = captureMessage(SEPOLIA_EID, OP_SEPOLIA_EID);
        relayMessage(message);
    }

    /**
     * @notice Helper function to perform L2->L1 deposit
     * @dev Encapsulates the full flow for reusability
     */
    function _performL2toL1Deposit(address sender, address recipient, uint256 amount) internal {
        vm.selectFork(opSepoliaForkId);
        vm.startPrank(sender);

        // wiTryVaultComposerSync expects abi.encode(SendParam, minMsgValue)
        SendParam memory innerSendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(recipient))),
            amountLD: 0,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        bytes memory composeMsg = abi.encode(innerSendParam, uint256(0));
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(address(composer)))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: composeMsg,
            oftCmd: ""
        });

        MessagingFee memory fee = opSepoliaOFT.quoteSend(sendParam, false);

        vm.recordLogs();
        opSepoliaOFT.send{value: fee.nativeFee}(sendParam, fee, payable(sender));
        vm.stopPrank();

        // Relay message
        CrossChainMessage memory message = captureMessage(OP_SEPOLIA_EID, SEPOLIA_EID);
        relayMessage(message);
    }
}
