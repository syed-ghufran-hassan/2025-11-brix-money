// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CrossChainTestBase} from "./CrossChainTestBase.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessagingFee, SendParam, IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * @title Step5_BasicOFTTransferTest
 * @notice Tests basic iTRY crosschain transfers (L1<->L2)
 * @dev Implements Step 5 of the CrossChain Testing Implementation Guide
 *
 * Test Scope:
 * - L1->L2: Lock iTRY on Sepolia, mint on OP Sepolia
 * - L2->L1: Burn iTRY on OP Sepolia, unlock on Sepolia
 * - Supply conservation across chains
 * - Event emission verification
 *
 * Success Criteria:
 * - All 4 tests pass
 * - No tokens lost or created
 * - Balances correct on both chains
 * - PacketSent events captured
 */
contract Step5_BasicOFTTransferTest is CrossChainTestBase {
    using OptionsBuilder for bytes;

    uint256 constant TRANSFER_AMOUNT = 100 ether;
    uint128 constant GAS_LIMIT = 200000;

    function setUp() public override {
        super.setUp();
        deployAllContracts();

        console.log("\n=== Step 5: Basic iTRY Crosschain Transfer Tests ===");
        console.log("Transfer Amount:", TRANSFER_AMOUNT);
        console.log("Gas Limit:", GAS_LIMIT);
    }

    /**
     * @notice Test 1: L1->L2 iTRY Transfer
     * @dev Locks iTRY on Sepolia, mints on OP Sepolia
     *
     * Flow:
     * 1. Mint iTRY to userL1 on Sepolia
     * 2. Approve adapter to spend
     * 3. Send iTRY to OP Sepolia
     * 4. Capture and relay message
     * 5. Verify balances on both chains
     */
    function test_L1_to_L2_iTRY_Transfer() public {
        console.log("\n=== Test 1: L1->L2 iTRY Transfer ===");

        // Step 1: Setup - Mint iTRY to userL1 on Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";

        uint256 userL1BalanceBefore;
        uint256 adapterBalanceBefore;

        {
            vm.prank(deployer);
            sepoliaITryToken.mint(userL1, TRANSFER_AMOUNT);

            userL1BalanceBefore = sepoliaITryToken.balanceOf(userL1);
            adapterBalanceBefore = sepoliaITryToken.balanceOf(address(sepoliaAdapter));

            console.log("Initial State (Sepolia):");
            console.log("  userL1 balance:", userL1BalanceBefore);
            console.log("  adapter balance:", adapterBalanceBefore);

            assertEq(userL1BalanceBefore, TRANSFER_AMOUNT, "User should have 100 iTRY");
        }

        // Step 2: Approve adapter to spend iTRY
        vm.startPrank(userL1);
        sepoliaITryToken.approve(address(sepoliaAdapter), TRANSFER_AMOUNT);
        console.log("  Approved adapter to spend iTRY");
        console.log("  Using adapter at:", address(sepoliaAdapter));

        // Step 3: Build LayerZero send parameters
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: OP_SEPOLIA_EID,
            to: bytes32(uint256(uint160(userL1))),
            amountLD: TRANSFER_AMOUNT,
            minAmountLD: TRANSFER_AMOUNT,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Quote the messaging fee
        MessagingFee memory fee = sepoliaAdapter.quoteSend(sendParam, false);
        console.log("  Messaging fee quoted successfully");
        console.log("  Messaging fee:", fee.nativeFee);

        // Step 4: Send iTRY cross-chain
        console.log("\nSending iTRY from Sepolia to OP Sepolia...");
        vm.recordLogs();
        sepoliaAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userL1));
        vm.stopPrank();

        // Verify tokens locked on Sepolia
        uint256 userL1BalanceAfterSend = sepoliaITryToken.balanceOf(userL1);
        uint256 adapterBalanceAfterSend = sepoliaITryToken.balanceOf(address(sepoliaAdapter));

        console.log("\nAfter Send (Sepolia):");
        console.log("  userL1 balance:", userL1BalanceAfterSend);
        console.log("  adapter balance (locked):", adapterBalanceAfterSend);

        assertEq(userL1BalanceAfterSend, 0, "User should have 0 iTRY after send");
        assertEq(adapterBalanceAfterSend, adapterBalanceBefore + TRANSFER_AMOUNT, "Adapter should have locked iTRY");

        // Step 5: Capture and relay the message
        console.log("\nRelaying message to OP Sepolia...");
        CrossChainMessage memory message = captureMessage(SEPOLIA_EID, OP_SEPOLIA_EID);

        console.log("Message captured:");
        console.log("  srcEid:", message.srcEid);
        console.log("  dstEid:", message.dstEid);
        console.logBytes32(message.guid);

        relayMessage(message);

        // Step 6: Verify tokens minted on OP Sepolia
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";

        uint256 userL1BalanceOnL2 = opSepoliaOFT.balanceOf(userL1);
        uint256 totalSupplyL2 = opSepoliaOFT.totalSupply();

        console.log("\nAfter Relay (OP Sepolia):");
        console.log("  userL1 balance:", userL1BalanceOnL2);
        console.log("  Total supply:", totalSupplyL2);

        assertEq(userL1BalanceOnL2, TRANSFER_AMOUNT, "User should have 100 iTRY on L2");
        assertEq(totalSupplyL2, TRANSFER_AMOUNT, "Total supply on L2 should be 100 iTRY");

        console.log("\n[SUCCESS] L1->L2 Transfer Complete!");
        console.log("  [OK] 100 iTRY locked on Sepolia");
        console.log("  [OK] 100 iTRY minted on OP Sepolia");
        console.log("  [OK] User balance correct on both chains");
    }

    /**
     * @notice Test 2: L2->L1 iTRY Return Transfer
     * @dev Burns iTRY on OP Sepolia, unlocks on Sepolia
     *
     * Flow:
     * 1. First transfer L1->L2 to have iTRY on L2
     * 2. Send iTRY back from OP Sepolia to Sepolia
     * 3. Capture and relay message
     * 4. Verify balances - should complete round-trip
     */
    function test_L2_to_L1_iTRY_Transfer() public {
        console.log("\n=== Test 2: L2->L1 iTRY Return Transfer ===");

        // Step 1: First do L1->L2 transfer to get iTRY on L2
        console.log("Setting up: Transferring iTRY to OP Sepolia first...");
        test_L1_to_L2_iTRY_Transfer();

        // Now userL1 has 100 iTRY on OP Sepolia
        // Step 2: Send iTRY back from L2 to L1
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";

        uint256 userL1BalanceBeforeL2 = opSepoliaOFT.balanceOf(userL1);
        uint256 totalSupplyBeforeL2 = opSepoliaOFT.totalSupply();

        console.log("\nInitial State (OP Sepolia):");
        console.log("  userL1 balance:", userL1BalanceBeforeL2);
        console.log("  Total supply:", totalSupplyBeforeL2);

        assertEq(userL1BalanceBeforeL2, TRANSFER_AMOUNT, "User should have 100 iTRY on L2");

        // Step 3: Build send parameters for return journey
        vm.startPrank(userL1);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: SEPOLIA_EID,
            to: bytes32(uint256(uint160(userL1))),
            amountLD: TRANSFER_AMOUNT,
            minAmountLD: TRANSFER_AMOUNT,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = opSepoliaOFT.quoteSend(sendParam, false);
        console.log("  Messaging fee:", fee.nativeFee);

        // Step 4: Send iTRY back to Sepolia
        console.log("\nSending iTRY from OP Sepolia back to Sepolia...");
        vm.recordLogs();
        opSepoliaOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userL1));
        vm.stopPrank();

        // Verify tokens burned on L2
        uint256 userL1BalanceAfterSendL2 = opSepoliaOFT.balanceOf(userL1);
        uint256 totalSupplyAfterSendL2 = opSepoliaOFT.totalSupply();

        console.log("\nAfter Send (OP Sepolia):");
        console.log("  userL1 balance:", userL1BalanceAfterSendL2);
        console.log("  Total supply:", totalSupplyAfterSendL2);

        assertEq(userL1BalanceAfterSendL2, 0, "User should have 0 iTRY on L2 after send");
        assertEq(totalSupplyAfterSendL2, 0, "Total supply on L2 should be 0 (burned)");

        // Step 5: Capture and relay message back to L1
        console.log("\nRelaying message back to Sepolia...");
        CrossChainMessage memory message = captureMessage(OP_SEPOLIA_EID, SEPOLIA_EID);

        console.log("Message captured:");
        console.log("  srcEid:", message.srcEid);
        console.log("  dstEid:", message.dstEid);
        console.logBytes32(message.guid);

        relayMessage(message);

        // Step 6: Verify tokens unlocked on Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";

        uint256 userL1FinalBalance = sepoliaITryToken.balanceOf(userL1);
        uint256 adapterFinalBalance = sepoliaITryToken.balanceOf(address(sepoliaAdapter));

        console.log("\nAfter Relay (Sepolia):");
        console.log("  userL1 balance:", userL1FinalBalance);
        console.log("  adapter balance:", adapterFinalBalance);

        assertEq(userL1FinalBalance, TRANSFER_AMOUNT, "User should have original 100 iTRY back");
        assertEq(adapterFinalBalance, 0, "Adapter should have unlocked all iTRY");

        console.log("\n[SUCCESS] L2->L1 Return Transfer Complete!");
        console.log("  [OK] 100 iTRY burned on OP Sepolia");
        console.log("  [OK] 100 iTRY unlocked on Sepolia");
        console.log("  [OK] Round-trip successful - user has original balance");
    }

    /**
     * @notice Test 3: Supply Conservation Across Chains
     * @dev Verifies no tokens are lost or created during transfers
     *
     * Invariant: Total supply L1 + Total supply L2 = Constant
     *
     * Flow:
     * 1. Record initial total supply across chains
     * 2. Execute L1->L2 transfer
     * 3. Verify total supply unchanged
     * 4. Execute L2->L1 transfer
     * 5. Verify total supply still unchanged
     */
    function test_Supply_Conservation_Across_Chains() public {
        console.log("\n=== Test 3: Supply Conservation Across Chains ===");

        // Step 1: Get initial total supply
        uint256 initialTotalSupply = getTotalSupplyAcrossChains();
        console.log("Initial total supply across chains:", initialTotalSupply);
        assertEq(initialTotalSupply, 0, "Should start with 0 total supply");

        // Step 2: Mint iTRY on Sepolia
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        vm.prank(deployer);
        sepoliaITryToken.mint(userL1, TRANSFER_AMOUNT);

        uint256 totalAfterMint = getTotalSupplyAcrossChains();
        console.log("Total supply after minting on L1:", totalAfterMint);
        assertEq(totalAfterMint, TRANSFER_AMOUNT, "Total should equal minted amount");

        // Step 3: Transfer L1->L2
        console.log("\nExecuting L1->L2 transfer...");
        vm.selectFork(sepoliaForkId);
        vm.startPrank(userL1);
        sepoliaITryToken.approve(address(sepoliaAdapter), TRANSFER_AMOUNT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: OP_SEPOLIA_EID,
            to: bytes32(uint256(uint160(userL1))),
            amountLD: TRANSFER_AMOUNT,
            minAmountLD: TRANSFER_AMOUNT,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = sepoliaAdapter.quoteSend(sendParam, false);
        vm.recordLogs();
        sepoliaAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userL1));
        vm.stopPrank();

        CrossChainMessage memory message = captureMessage(SEPOLIA_EID, OP_SEPOLIA_EID);
        relayMessage(message);

        // Step 4: Verify supply accounting after L1->L2
        // Note: In OFT adapter system, L1 tokens are LOCKED (not burned)
        // So total supply = locked on L1 + minted on L2
        uint256 totalAfterL1toL2 = getTotalSupplyAcrossChains();
        console.log("Total supply after L1->L2 transfer:", totalAfterL1toL2);

        logSupplyBreakdown("After L1->L2");

        // Verify the accounting: locked on L1 (100) + minted on L2 (100) = 200
        assertEq(totalAfterL1toL2, TRANSFER_AMOUNT * 2, "Total supply should be locked L1 + minted L2");

        // Verify conservation through adapter balance
        vm.selectFork(sepoliaForkId);
        uint256 lockedOnL1 = sepoliaITryToken.balanceOf(address(sepoliaAdapter));
        vm.selectFork(opSepoliaForkId);
        uint256 mintedOnL2 = opSepoliaOFT.totalSupply();

        assertEq(lockedOnL1, TRANSFER_AMOUNT, "Should have locked 100 on L1");
        assertEq(mintedOnL2, TRANSFER_AMOUNT, "Should have minted 100 on L2");
        assertEq(lockedOnL1, mintedOnL2, "Locked amount should equal minted amount");

        // Step 5: Transfer L2->L1
        console.log("\nExecuting L2->L1 transfer...");
        vm.selectFork(opSepoliaForkId);
        vm.startPrank(userL1);

        sendParam.dstEid = SEPOLIA_EID;
        fee = opSepoliaOFT.quoteSend(sendParam, false);
        vm.recordLogs();
        opSepoliaOFT.send{value: fee.nativeFee}(sendParam, fee, payable(userL1));
        vm.stopPrank();

        message = captureMessage(OP_SEPOLIA_EID, SEPOLIA_EID);
        relayMessage(message);

        // Step 6: Verify supply after round-trip
        // After burning on L2 and unlocking on L1, we're back to original state
        uint256 totalAfterRoundTrip = getTotalSupplyAcrossChains();
        console.log("Total supply after round-trip:", totalAfterRoundTrip);

        logSupplyBreakdown("After L2->L1");

        // Back to original: 100 on L1, 0 on L2
        assertEq(totalAfterRoundTrip, TRANSFER_AMOUNT, "Total supply should be back to original after round-trip");

        // Verify all tokens unlocked on L1
        vm.selectFork(sepoliaForkId);
        uint256 lockedAfterReturn = sepoliaITryToken.balanceOf(address(sepoliaAdapter));
        assertEq(lockedAfterReturn, 0, "All tokens should be unlocked on L1");

        // Verify all tokens burned on L2
        vm.selectFork(opSepoliaForkId);
        uint256 supplyAfterReturn = opSepoliaOFT.totalSupply();
        assertEq(supplyAfterReturn, 0, "All tokens should be burned on L2");

        console.log("\n[SUCCESS] Supply Conservation Verified!");
        console.log("  [OK] Lock/unlock mechanism working correctly");
        console.log("  [OK] Mint/burn mechanism working correctly");
        console.log("  [OK] No tokens lost during round-trip");
    }

    /**
     * @notice Test 4: PacketSent Event Emission
     * @dev Verifies LayerZero PacketSent events are emitted correctly
     *
     * Flow:
     * 1. Send iTRY cross-chain
     * 2. Capture logs
     * 3. Verify PacketSent event present
     * 4. Verify event contains correct data
     */
    function test_PacketSent_Event_Emission() public {
        console.log("\n=== Test 4: PacketSent Event Emission ===");

        // Setup
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";

        vm.prank(deployer);
        sepoliaITryToken.mint(userL1, TRANSFER_AMOUNT);

        vm.startPrank(userL1);
        sepoliaITryToken.approve(address(sepoliaAdapter), TRANSFER_AMOUNT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: OP_SEPOLIA_EID,
            to: bytes32(uint256(uint160(userL1))),
            amountLD: TRANSFER_AMOUNT,
            minAmountLD: TRANSFER_AMOUNT,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        MessagingFee memory fee = sepoliaAdapter.quoteSend(sendParam, false);

        // Record logs and send
        console.log("Sending iTRY and recording logs...");
        vm.recordLogs();
        sepoliaAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(userL1));
        vm.stopPrank();

        // Capture and verify message
        console.log("Capturing message from logs...");
        CrossChainMessage memory message = captureMessage(SEPOLIA_EID, OP_SEPOLIA_EID);

        // Verify message fields
        console.log("\nVerifying message structure:");
        console.log("  srcEid:", message.srcEid);
        console.log("  dstEid:", message.dstEid);
        console.logBytes32(message.sender);
        console.logBytes32(message.receiver);
        console.logBytes32(message.guid);

        assertEq(message.srcEid, SEPOLIA_EID, "Source EID should be Sepolia");
        assertEq(message.dstEid, OP_SEPOLIA_EID, "Destination EID should be OP Sepolia");
        assertEq(message.sender, bytes32(uint256(uint160(address(sepoliaAdapter)))), "Sender should be Sepolia adapter");
        assertEq(
            message.receiver, bytes32(uint256(uint160(address(opSepoliaOFT)))), "Receiver should be OP Sepolia OFT"
        );
        assertTrue(message.guid != bytes32(0), "GUID should not be zero");
        assertTrue(message.payload.length > 0, "Payload should not be empty");
        assertTrue(message.options.length > 0, "Options should not be empty");

        console.log("\n[SUCCESS] PacketSent Event Verification Complete!");
        console.log("  [OK] Event captured from logs");
        console.log("  [OK] srcEid and dstEid correct");
        console.log("  [OK] Sender and receiver addresses correct");
        console.log("  [OK] GUID generated");
        console.log("  [OK] Payload and options present");
    }

    // ============ Helper Functions ============

    /**
     * @notice Gets total iTRY supply across both chains
     * @return totalSupply Sum of Sepolia and OP Sepolia supplies
     */
    function getTotalSupplyAcrossChains() internal returns (uint256 totalSupply) {
        uint256 sepoliaSupply;
        uint256 opSepoliaSupply;

        vm.selectFork(sepoliaForkId);
        sepoliaSupply = sepoliaITryToken.totalSupply();

        vm.selectFork(opSepoliaForkId);
        opSepoliaSupply = opSepoliaOFT.totalSupply();

        totalSupply = sepoliaSupply + opSepoliaSupply;
    }

    /**
     * @notice Logs supply breakdown across chains
     * @param label Description label for log output
     */
    function logSupplyBreakdown(string memory label) internal {
        uint256 sepoliaSupply;
        uint256 opSepoliaSupply;

        vm.selectFork(sepoliaForkId);
        sepoliaSupply = sepoliaITryToken.totalSupply();

        vm.selectFork(opSepoliaForkId);
        opSepoliaSupply = opSepoliaOFT.totalSupply();

        console.log("\nSupply Breakdown -", label);
        console.log("  Sepolia supply:", sepoliaSupply);
        console.log("  OP Sepolia supply:", opSepoliaSupply);
        console.log("  Total:", sepoliaSupply + opSepoliaSupply);
    }

    /**
     * @notice Logs balance state for debugging
     * @param label Description label for log output
     */
    function logBalanceState(string memory label) internal {
        console.log("\nBalance State -", label);

        vm.selectFork(sepoliaForkId);
        console.log("Sepolia:");
        console.log("  userL1:", sepoliaITryToken.balanceOf(userL1));
        console.log("  adapter:", sepoliaITryToken.balanceOf(address(sepoliaAdapter)));
        console.log("  total supply:", sepoliaITryToken.totalSupply());

        vm.selectFork(opSepoliaForkId);
        console.log("OP Sepolia:");
        console.log("  userL1:", opSepoliaOFT.balanceOf(userL1));
        console.log("  total supply:", opSepoliaOFT.totalSupply());
    }
}
