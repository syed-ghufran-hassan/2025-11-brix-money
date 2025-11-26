// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IUnstakeMessenger} from "../../../src/token/wiTRY/crosschain/interfaces/IUnstakeMessenger.sol";

/**
 * @title VaultComposerStructDecodingTest
 * @notice Tests to validate the fix for Panic(0x41) ABI decoding errors
 * @dev Tests both the correct (struct decode) and incorrect (bytes decode) patterns
 *      to prove the bug exists and validate the fix
 */
contract VaultComposerStructDecodingTest is Test {
    uint16 constant MSG_TYPE_UNSTAKE = 1;

    /**
     * @notice Test direct struct decoding with empty extraOptions
     * @dev This is the correct Solution A pattern that should work
     */
    function test_DirectStructDecoding_EmptyOptions() public pure {
        // Setup: Create message as UnstakeMessenger encodes it
        address testUser = address(0x1234567890123456789012345678901234567890);
        bytes memory emptyOptions = "";

        IUnstakeMessenger.UnstakeMessage memory originalMsg =
            IUnstakeMessenger.UnstakeMessage({user: testUser, extraOptions: emptyOptions});

        // Encode as UnstakeMessenger does: abi.encode(MSG_TYPE_UNSTAKE, UnstakeMessage struct)
        bytes memory encodedMessage = abi.encode(MSG_TYPE_UNSTAKE, originalMsg);

        // Test: Direct struct decode (Solution A)
        (uint16 msgType, IUnstakeMessenger.UnstakeMessage memory decodedMsg) =
            abi.decode(encodedMessage, (uint16, IUnstakeMessenger.UnstakeMessage));

        // Assert: Values should match
        assertEq(msgType, MSG_TYPE_UNSTAKE, "Message type mismatch");
        assertEq(decodedMsg.user, testUser, "User address mismatch");
        assertEq(decodedMsg.extraOptions.length, 0, "Extra options should be empty");
        assertEq(decodedMsg.extraOptions, emptyOptions, "Extra options content mismatch");
    }

    /**
     * @notice Test direct struct decoding with non-empty extraOptions
     * @dev Validates that the fix works with LayerZero gas options
     */
    function test_DirectStructDecoding_WithOptions() public pure {
        // Setup: Create message with non-empty extraOptions
        address testUser = address(0x9876543210987654321098765432109876543210);
        bytes memory gasOptions = hex"0003010011010000000000000000000000000000ea60"; // LayerZero TYPE_3 options

        IUnstakeMessenger.UnstakeMessage memory originalMsg =
            IUnstakeMessenger.UnstakeMessage({user: testUser, extraOptions: gasOptions});

        // Encode as UnstakeMessenger does
        bytes memory encodedMessage = abi.encode(MSG_TYPE_UNSTAKE, originalMsg);

        // Test: Direct struct decode (Solution A)
        (uint16 msgType, IUnstakeMessenger.UnstakeMessage memory decodedMsg) =
            abi.decode(encodedMessage, (uint16, IUnstakeMessenger.UnstakeMessage));

        // Assert: Values should match including non-empty options
        assertEq(msgType, MSG_TYPE_UNSTAKE, "Message type mismatch");
        assertEq(decodedMsg.user, testUser, "User address mismatch");
        assertEq(decodedMsg.extraOptions.length, gasOptions.length, "Extra options length mismatch");
        assertEq(decodedMsg.extraOptions, gasOptions, "Extra options content mismatch");
    }

    /**
     * @notice Test that current bytes decode pattern fails with Panic(0x41)
     * @dev This proves the bug exists in the current VaultComposer implementation
     */
    function test_CurrentBytesDecoding_Fails() public {
        // Setup: Create message as UnstakeMessenger encodes it (struct encoding)
        address testUser = address(0x1111111111111111111111111111111111111111);
        bytes memory emptyOptions = "";

        IUnstakeMessenger.UnstakeMessage memory originalMsg =
            IUnstakeMessenger.UnstakeMessage({user: testUser, extraOptions: emptyOptions});

        // Encode as UnstakeMessenger does: struct encoding
        bytes memory encodedMessage = abi.encode(MSG_TYPE_UNSTAKE, originalMsg);

        // Test: Try two-step bytes decode (current broken pattern)
        // This should fail with Panic(0x41) - array access out of bounds
        // We need to wrap the decode in a try-catch to properly test it
        try this._attemptBrokenDecode(encodedMessage) {
            // If it doesn't revert, the test should fail
            fail("Expected Panic(0x41) but decode succeeded");
        } catch (bytes memory reason) {
            // Check that it's a Panic error with code 0x41
            bytes4 panicSelector = bytes4(keccak256("Panic(uint256)"));
            require(bytes4(reason) == panicSelector, "Wrong error type");

            // Extract panic code (should be 0x41)
            uint256 panicCode;
            assembly {
                panicCode := mload(add(reason, 0x24))
            }
            assertEq(panicCode, 0x41, "Expected Panic(0x41)");
        }
    }

    /**
     * @notice Helper function to attempt the broken decode pattern
     * @dev Must be external to use try-catch
     */
    function _attemptBrokenDecode(bytes memory encodedMessage) external pure {
        // First decode: (uint16, bytes) - This expects nested encoding but we have struct
        (, bytes memory msgData) = abi.decode(encodedMessage, (uint16, bytes));

        // Second decode: This will fail because msgData is not properly encoded
        abi.decode(msgData, (address, bytes));
    }

    /**
     * @notice Test fuzz: Direct struct decode with random user addresses
     * @dev Validates fix works with any valid address
     */
    function testFuzz_DirectStructDecoding_RandomUser(address randomUser) public pure {
        // Skip zero address (invalid in real usage)
        vm.assume(randomUser != address(0));

        bytes memory emptyOptions = "";

        IUnstakeMessenger.UnstakeMessage memory originalMsg =
            IUnstakeMessenger.UnstakeMessage({user: randomUser, extraOptions: emptyOptions});

        bytes memory encodedMessage = abi.encode(MSG_TYPE_UNSTAKE, originalMsg);

        // Test: Direct struct decode
        (, IUnstakeMessenger.UnstakeMessage memory decodedMsg) =
            abi.decode(encodedMessage, (uint16, IUnstakeMessenger.UnstakeMessage));

        // Assert: User should match
        assertEq(decodedMsg.user, randomUser, "User address mismatch in fuzz test");
    }

    /**
     * @notice Test fuzz: Direct struct decode with random extraOptions
     * @dev Validates fix works with any bytes payload
     */
    function testFuzz_DirectStructDecoding_RandomOptions(bytes memory randomOptions) public pure {
        // Limit size to reasonable LayerZero options (max 1KB)
        vm.assume(randomOptions.length <= 1024);

        address testUser = address(0x2222222222222222222222222222222222222222);

        IUnstakeMessenger.UnstakeMessage memory originalMsg =
            IUnstakeMessenger.UnstakeMessage({user: testUser, extraOptions: randomOptions});

        bytes memory encodedMessage = abi.encode(MSG_TYPE_UNSTAKE, originalMsg);

        // Test: Direct struct decode
        (, IUnstakeMessenger.UnstakeMessage memory decodedMsg) =
            abi.decode(encodedMessage, (uint16, IUnstakeMessenger.UnstakeMessage));

        // Assert: Options should match
        assertEq(decodedMsg.extraOptions, randomOptions, "Extra options mismatch in fuzz test");
    }
}
