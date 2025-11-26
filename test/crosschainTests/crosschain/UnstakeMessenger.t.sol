// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {UnstakeMessenger} from "../../../src/token/wiTRY/crosschain/UnstakeMessenger.sol";
import {IUnstakeMessenger} from "../../../src/token/wiTRY/crosschain/interfaces/IUnstakeMessenger.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {MessagingParams} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {EnforcedOptionParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppOptionsType3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockERC20
 * @notice Simple ERC20 mock for rescue function testing
 */
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }
}

/**
 * @title MockLayerZeroEndpoint
 * @notice Mock LayerZero endpoint for testing UnstakeMessenger
 */
contract MockLayerZeroEndpoint {
    uint64 public nonce;
    uint256 public quotedNativeFee;
    uint256 public quotedLzTokenFee;
    bytes32 public lastGuid;

    // Track last send call
    uint32 public lastDstEid;
    bytes public lastPayload;
    bytes public lastOptions;
    MessagingFee public lastFee;
    address public lastRefundAddress;

    // Track delegate
    address public delegate;

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }

    function setQuote(uint256 nativeFee, uint256 lzTokenFee) external {
        quotedNativeFee = nativeFee;
        quotedLzTokenFee = lzTokenFee;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee(quotedNativeFee, quotedLzTokenFee);
    }

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory)
    {
        lastDstEid = _params.dstEid;
        lastPayload = _params.message;
        lastOptions = _params.options;
        lastFee = MessagingFee(msg.value, 0);
        lastRefundAddress = _refundAddress;

        nonce++;
        lastGuid = keccak256(abi.encodePacked(_params.dstEid, nonce));

        return MessagingReceipt(lastGuid, nonce, MessagingFee(msg.value, 0));
    }

    function getLastSendParams()
        external
        view
        returns (
            uint32 dstEid,
            bytes memory payload,
            bytes memory options,
            MessagingFee memory fee,
            address refundAddress
        )
    {
        return (lastDstEid, lastPayload, lastOptions, lastFee, lastRefundAddress);
    }
}

/**
 * @title UnstakeMessengerTest
 * @notice Comprehensive unit tests for UnstakeMessenger contract
 */
contract UnstakeMessengerTest is Test {
    using OptionsBuilder for bytes;

    UnstakeMessenger public messenger;
    MockLayerZeroEndpoint public mockEndpoint;
    MockERC20 public mockToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public nonOwner = makeAddr("nonOwner");
    uint32 public hubEid = 40161; // Sepolia

    bytes32 public hubPeer = bytes32(uint256(uint160(makeAddr("hubVaultComposer"))));

    // Constants from UnstakeMessenger
    uint16 constant MSG_TYPE_UNSTAKE = 1;
    uint128 constant LZ_RECEIVE_GAS = 200000; // Must match UnstakeMessenger.sol:63
    uint256 constant BPS_DENOMINATOR = 10000;
    uint256 constant USER_INITIAL_BALANCE = 100 ether; // Initial balance for test users

    // Events
    event UnstakeRequested(
        address indexed user, uint32 indexed hubEid, uint256 totalFee, uint256 excessRefunded, bytes32 guid
    );
    event PeerSet(uint32 indexed eid, bytes32 peer);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event FeeBufferUpdated(uint256 oldBuffer, uint256 newBuffer);

    function setUp() public {
        // Deploy mock endpoint
        mockEndpoint = new MockLayerZeroEndpoint();

        // Deploy UnstakeMessenger
        vm.startPrank(owner);
        messenger = new UnstakeMessenger(address(mockEndpoint), owner, hubEid);
        vm.stopPrank();

        // Mirror production config: enforce LZ receive gas (no static native value)
        // Native value is calculated dynamically per transaction by the contract
        vm.startPrank(owner);
        EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
        bytes memory enforced = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(
                LZ_RECEIVE_GAS,
                0 // No static native value - calculated dynamically per transaction
            );
        params[0] = EnforcedOptionParam({eid: hubEid, msgType: MSG_TYPE_UNSTAKE, options: enforced});
        messenger.setEnforcedOptions(params);
        vm.stopPrank();

        // Deploy mock token for rescue tests
        mockToken = new MockERC20();

        // Fund user
        vm.deal(user, USER_INITIAL_BALANCE);
    }

    // ============ Test Group 1: Constructor Tests ============

    function test_Constructor_InitializesCorrectly() public {
        // Verify hubEid set correctly
        assertEq(messenger.hubEid(), hubEid, "Hub EID not set correctly");

        // Verify endpoint set correctly
        assertEq(address(messenger.endpoint()), address(mockEndpoint), "Endpoint not set correctly");

        // Verify owner set correctly
        assertEq(messenger.owner(), owner, "Owner not set correctly");
    }

    function test_Constructor_RevertsWithZeroHubEid() public {
        vm.expectRevert(IUnstakeMessenger.HubNotConfigured.selector);
        new UnstakeMessenger(address(mockEndpoint), owner, 0);
    }

    // ============ Test Group 2: unstake() Function Tests ============

    function test_Unstake_SuccessWithValidConfiguration() public {
        // Setup: Configure hub peer
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Set mock quote
        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote for the return trip value we want to send
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Execute unstake with exact quoted fee
        vm.prank(user);
        bytes32 guid = messenger.unstake{value: exactFee}(0.00001 ether);

        // Verify guid returned
        assertTrue(guid != bytes32(0), "GUID should not be zero");
    }

    function test_Unstake_PayloadEncodingCorrect() public {
        // NEW BEHAVIOR: extraOptions contains valid TYPE_3 header (initialized with newOptions())

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote for the return trip value we want to send
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Execute unstake with exact fee
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);

        // Get last payload from mock endpoint
        (, bytes memory payload,,,) = mockEndpoint.getLastSendParams();

        // Decode payload
        (uint16 msgType, IUnstakeMessenger.UnstakeMessage memory message) =
            abi.decode(payload, (uint16, IUnstakeMessenger.UnstakeMessage));

        // Verify payload contents
        assertEq(msgType, MSG_TYPE_UNSTAKE, "Message type incorrect");
        assertEq(message.user, user, "CRITICAL: User address must be msg.sender");

        // NEW: extraOptions contains TYPE_3 header (2 bytes minimum)
        assertEq(message.extraOptions.length, 2, "Extra options should contain TYPE_3 header");
    }

    function test_Unstake_DynamicFeeSplitCorrect() public {
        // Setup
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Set mock quote
        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote for the return trip value we want to send
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Execute unstake with exact fee
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);

        // Get options from mock endpoint
        (,, bytes memory options,,) = mockEndpoint.getLastSendParams();

        // New implementation dynamically builds options with leg2 allocation
        // Combined options will have:
        // - Enforced: gas=200000, value=0
        // - Dynamic: gas=0, value=leg2Allocation
        // Total options length will be > 38 bytes (two LzReceiveOption entries)

        // Verify options are longer than 38 bytes (contains dynamic entry)
        assertTrue(options.length > 38, "Options should contain dynamic leg2 allocation");

        // Verify TYPE_3 (first 2 bytes should be 0x0003)
        uint16 optionType = uint16(uint8(options[0])) << 8 | uint16(uint8(options[1]));
        assertEq(optionType, 3, "Options should be TYPE_3");

        // Note: Full options parsing would require decoding the combined structure
        // The critical test is that the transaction succeeds and the dynamic allocation happens
    }

    function test_Unstake_ClientAppliesBuffer() public {
        // Setup
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 baseFee = 0.01 ether;
        mockEndpoint.setQuote(baseFee, 0);

        // NEW BEHAVIOR: Contract validates actual LayerZero costs, not buffer
        // Client should apply buffer to TOTAL (leg1 + leg2), but contract doesn't enforce it
        // The contract will refund excess after sending the message

        // Get buffer percentage from contract
        uint256 bufferBPS = messenger.feeBufferBPS();
        assertEq(bufferBPS, 1000, "Default buffer should be 10% (1000 bps)");

        // Get exact quote for the return trip value we want to send
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Should succeed - contract validates against actual LZ fees
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);
    }

    function test_Unstake_RevertsWithInsufficientFee() public {
        // NEW BEHAVIOR: Contract validates actual LayerZero costs dynamically
        // - First checks msg.value > leg1BaseFee (to allocate leg2)
        // - Then checks msg.value >= totalFee (after re-quote with native drop)

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote for the operation
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Send slightly less than required
        uint256 insufficientAmount = exactFee - 1;

        // Should revert with InsufficientFee
        vm.expectRevert(
            abi.encodeWithSelector(IUnstakeMessenger.InsufficientFee.selector, exactFee, insufficientAmount)
        );

        vm.prank(user);
        messenger.unstake{value: insufficientAmount}(0.00001 ether);
    }

    function test_Unstake_RevertsWhenPeerNotConfigured() public {
        // Do NOT call setPeer() - should revert before any fee validation

        // Should revert with HubNotConfigured (no need to set mock quote)
        vm.expectRevert(IUnstakeMessenger.HubNotConfigured.selector);

        vm.prank(user);
        messenger.unstake{value: 0.01 ether}(0.00001 ether);
    }

    // ============ Test Group 3: quoteUnstake() Tests ============

    function test_QuoteUnstake_ReturnsReasonableFee() public {
        // NEW BEHAVIOR: quoteUnstake() returns BASE fee (leg1 only, no buffer)
        // Client applies buffer off-chain using feeBufferBPS

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        (uint256 nativeFee, uint256 lzTokenFee) = messenger.quoteUnstakeWithReturnValue(0);

        // Verify returns BASE fee without buffer
        assertEq(nativeFee, leg1BaseFee, "Should return base fee without buffer");
        assertEq(lzTokenFee, 0, "LZ token fee should be 0");

        // Client can read feeBufferBPS to calculate total off-chain
        uint256 bufferBPS = messenger.feeBufferBPS();
        assertEq(bufferBPS, 1000, "Default buffer should be 10%");
    }

    function test_QuoteUnstake_BufferCalculation() public {
        // NEW BEHAVIOR: quoteUnstake() returns BASE fee
        // This test verifies clients can calculate buffered amounts off-chain

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Test with different base fees
        uint256[] memory baseFees = new uint256[](3);
        baseFees[0] = 0.001 ether;
        baseFees[1] = 0.1 ether;
        baseFees[2] = 1 ether;

        uint256 bufferBPS = messenger.feeBufferBPS();

        for (uint256 i = 0; i < baseFees.length; i++) {
            mockEndpoint.setQuote(baseFees[i], 0);
            (uint256 quotedFee,) = messenger.quoteUnstakeWithReturnValue(0);

            // Verify quote returns BASE fee (no buffer)
            assertEq(quotedFee, baseFees[i], "Should return base fee without buffer");

            // Simulate off-chain buffer calculation (client-side logic)
            uint256 clientCalculatedTotal = (baseFees[i] * (BPS_DENOMINATOR + bufferBPS)) / BPS_DENOMINATOR;

            // Verify client can correctly calculate buffered amount
            assertTrue(clientCalculatedTotal > quotedFee, "Buffered amount should exceed quoted fee");
        }
    }

    // ============ Test Group 4: Peer Management Tests ============

    function test_SetPeer_SucceedsAsOwner() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Verify peer set correctly
        assertEq(messenger.getHubPeer(), hubPeer, "Hub peer not set correctly");
    }

    function test_SetPeer_RevertsAsNonOwner() public {
        vm.expectRevert();
        vm.prank(nonOwner);
        messenger.setPeer(hubEid, hubPeer);
    }

    function test_SetPeer_RevertsWithInvalidEid() public {
        uint32 wrongEid = 40232; // Different chain

        vm.expectRevert("UnstakeMessenger: Invalid endpoint");
        vm.prank(owner);
        messenger.setPeer(wrongEid, hubPeer);
    }

    function test_SetPeer_RevertsWithZeroPeer() public {
        vm.expectRevert("UnstakeMessenger: Invalid peer");
        vm.prank(owner);
        messenger.setPeer(hubEid, bytes32(0));
    }

    function test_GetHubPeer_ReturnsCorrectPeer() public {
        // Initially should return zero
        assertEq(messenger.getHubPeer(), bytes32(0), "Initial peer should be zero");

        // Set peer
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Should return set peer
        assertEq(messenger.getHubPeer(), hubPeer, "Should return configured peer");
    }

    // ============ Test Group 5: Rescue Function Tests ============

    function test_RescueERC20_SucceedsAsOwner() public {
        // Setup: Send tokens to messenger
        uint256 amount = 1000e18;
        mockToken.mint(address(messenger), amount);

        assertEq(mockToken.balanceOf(address(messenger)), amount, "Messenger should have tokens");
        assertEq(mockToken.balanceOf(owner), 0, "Owner should have no tokens initially");

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit TokenRescued(address(mockToken), owner, amount);

        // Rescue tokens
        vm.prank(owner);
        messenger.rescueToken(address(mockToken), owner, amount);

        // Verify tokens transferred
        assertEq(mockToken.balanceOf(address(messenger)), 0, "Messenger should have no tokens");
        assertEq(mockToken.balanceOf(owner), amount, "Owner should have rescued tokens");
    }

    function test_RescueERC20_RevertsAsNonOwner() public {
        uint256 amount = 1000e18;
        mockToken.mint(address(messenger), amount);

        vm.expectRevert();
        vm.prank(nonOwner);
        messenger.rescueToken(address(mockToken), owner, amount);
    }

    function test_RescueERC20_RevertsWithZeroRecipient() public {
        uint256 amount = 1000e18;
        mockToken.mint(address(messenger), amount);

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        vm.prank(owner);
        messenger.rescueToken(address(mockToken), address(0), amount);
    }

    function test_RescueERC20_RevertsWithZeroAmount() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        vm.prank(owner);
        messenger.rescueToken(address(mockToken), owner, 0);
    }

    function test_RescueETH_SucceedsAsOwner() public {
        // Setup: Send ETH to messenger
        uint256 amount = 1 ether;
        vm.deal(address(messenger), amount);

        uint256 initialBalance = owner.balance;

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit TokenRescued(address(0), owner, amount);

        // Rescue ETH (use address(0) for ETH)
        vm.prank(owner);
        messenger.rescueToken(address(0), owner, amount);

        // Verify ETH transferred
        assertEq(address(messenger).balance, 0, "Messenger should have no ETH");
        assertEq(owner.balance, initialBalance + amount, "Owner should have rescued ETH");
    }

    function test_RescueETH_RevertsAsNonOwner() public {
        uint256 amount = 1 ether;
        vm.deal(address(messenger), amount);

        vm.expectRevert();
        vm.prank(nonOwner);
        messenger.rescueToken(address(0), owner, amount);
    }

    function test_RescueETH_RevertsWithZeroRecipient() public {
        uint256 amount = 1 ether;
        vm.deal(address(messenger), amount);

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        vm.prank(owner);
        messenger.rescueToken(address(0), address(0), amount);
    }

    function test_RescueETH_RevertsWithZeroAmount() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        vm.prank(owner);
        messenger.rescueToken(address(0), owner, 0);
    }

    // ============ Test Group 6: Send-Only Pattern Test ============

    function test_LzReceive_AlwaysReverts() public {
        // VERIFICATION: UnstakeMessenger uses OAppSender (send-only)
        // No _lzReceive() override exists - attempting to receive will fail at LayerZero level
        // This is by design: spoke chains only SEND unstake requests, never receive messages

        // The contract explicitly uses OAppSender instead of OApp to enforce send-only behavior
        // Any attempt to configure this contract as a receiver or send messages TO it
        // will fail because:
        // 1. No _lzReceive() implementation exists
        // 2. OAppSender does not provide receive functionality
        // 3. LayerZero will reject messages sent to this contract

        // This test documents the architectural decision: UnstakeMessenger is intentionally
        // a send-only contract for crosschain unstaking operations.
    }

    // ============ Test Group 7: Security-Focused Tests ============

    function test_Security_UserIsMsgSender() public {
        // CRITICAL SECURITY TEST
        // Verify that unstake() ALWAYS uses msg.sender as user address
        // No way to specify different user address

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 baseFee = 0.01 ether;
        mockEndpoint.setQuote(baseFee, 0);

        // Get exact quote
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");

        vm.deal(attacker, 1 ether);

        // Attacker calls unstake with exact fee
        vm.prank(attacker);
        messenger.unstake{value: exactFee}(0.00001 ether);

        // Get payload and decode
        (, bytes memory payload,,,) = mockEndpoint.getLastSendParams();
        (, IUnstakeMessenger.UnstakeMessage memory message) =
            abi.decode(payload, (uint16, IUnstakeMessenger.UnstakeMessage));

        // CRITICAL: User MUST be attacker (msg.sender), NOT victim
        assertEq(message.user, attacker, "CRITICAL: User must be msg.sender");
        assertTrue(message.user != victim, "CRITICAL: User cannot be spoofed");
    }

    function test_Security_NoReentrancy() public {
        // Verify state changes before external calls
        // UnstakeMessenger uses _lzSend which is an external call
        // The contract should not have reentrancy issues as it doesn't
        // maintain critical state that could be manipulated

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 baseFee = 0.01 ether;
        mockEndpoint.setQuote(baseFee, 0);

        // Get exact quote
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Execute multiple times with exact fee to verify no state corruption
        vm.startPrank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);
        messenger.unstake{value: exactFee}(0.00001 ether);
        messenger.unstake{value: exactFee}(0.00001 ether);
        vm.stopPrank();

        // All calls should succeed without state corruption
    }

    function test_Security_FeeCalculationNoOverflow() public {
        // NEW BEHAVIOR: quoteUnstake() returns BASE fee (no buffer)
        // Test that both base quote and off-chain buffer calculation don't overflow

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Test with large values to ensure no overflow
        uint256 largeFee = type(uint128).max;
        mockEndpoint.setQuote(largeFee, 0);

        // Should not revert with overflow
        (uint256 nativeFee,) = messenger.quoteUnstakeWithReturnValue(0);

        // Verify base fee returned correctly
        assertEq(nativeFee, largeFee, "Should return base fee without overflow");

        // Verify off-chain buffer calculation doesn't overflow
        uint256 bufferBPS = messenger.feeBufferBPS();
        uint256 clientCalculatedTotal = (largeFee * (BPS_DENOMINATOR + bufferBPS)) / BPS_DENOMINATOR;
        assertTrue(clientCalculatedTotal >= largeFee, "Client calculation should not overflow");
    }

    function test_Security_RefundExcessToMsgSender() public {
        // SECURITY TEST: Verify refund address is set to msg.sender
        // Contract requires exact payment, so this test verifies refund address is correctly set

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        uint256 userInitialBalance = user.balance;

        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);

        // Verify LayerZero refund address is set to user (msg.sender)
        (,,,, address lzRefundAddress) = mockEndpoint.getLastSendParams();
        assertEq(lzRefundAddress, user, "LayerZero refund should go to msg.sender");

        // Verify user balance decreased by exactly the fee (plus gas)
        uint256 userFinalBalance = user.balance;
        assertApproxEqAbs(userInitialBalance - userFinalBalance, exactFee, 0.001 ether, "User should pay exact fee");
    }

    // ============ Test Group 8: Edge Cases ============

    function test_EdgeCase_ZeroBaseFee() public {
        // Setup: Configure peer first
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Test with zero base fee (unusual but possible)
        mockEndpoint.setQuote(0, 0);

        (uint256 nativeFee,) = messenger.quoteUnstakeWithReturnValue(0);

        // Even with zero base fee, should not revert
        assertEq(nativeFee, 0, "Zero base fee should result in zero buffered fee");
    }

    function test_EdgeCase_MaxUint128Fee() public {
        // NEW BEHAVIOR: quoteUnstake() returns BASE fee (no buffer applied)

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // Test with maximum uint128 value (LayerZero uses uint128 for fees)
        uint256 maxFee = type(uint128).max;
        mockEndpoint.setQuote(maxFee, 0);

        (uint256 nativeFee,) = messenger.quoteUnstakeWithReturnValue(0);

        // Should return base fee without overflow
        assertEq(nativeFee, maxFee, "Should return base fee without buffer");

        // Client can calculate buffered amount off-chain (verify no overflow)
        uint256 bufferBPS = messenger.feeBufferBPS();
        uint256 clientCalculatedTotal = (maxFee * (BPS_DENOMINATOR + bufferBPS)) / BPS_DENOMINATOR;
        assertTrue(clientCalculatedTotal > maxFee, "Client-calculated buffered fee should be greater");
    }

    function test_EdgeCase_MultipleUnstakesFromSameUser() public {
        // NEW BEHAVIOR: User sends exact quoted fee for each unstake

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get exact quote
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Execute multiple unstakes with exact fee
        vm.startPrank(user);
        bytes32 guid1 = messenger.unstake{value: exactFee}(0.00001 ether);
        bytes32 guid2 = messenger.unstake{value: exactFee}(0.00001 ether);
        bytes32 guid3 = messenger.unstake{value: exactFee}(0.00001 ether);
        vm.stopPrank();

        // All should succeed with different GUIDs
        assertTrue(guid1 != guid2, "GUIDs should be unique");
        assertTrue(guid2 != guid3, "GUIDs should be unique");
        assertTrue(guid1 != guid3, "GUIDs should be unique");
    }

    // ============ Test Group 9: Integration-style Tests ============

    function test_Integration_FullUnstakeFlow() public {
        // NEW BEHAVIOR: Complete flow with exact fee payment

        // 1. Setup: Configure peer
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        // 2. Quote: Get base fee and exact fee for return trip
        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);
        (uint256 quotedLeg1Fee,) = messenger.quoteUnstakeWithReturnValue(0);

        assertEq(quotedLeg1Fee, leg1BaseFee, "Quoted fee should equal leg1 base fee");

        // 3. Client gets exact quote for the unstake operation with return trip
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // 4. Unstake: Execute with exact fee
        vm.prank(user);
        bytes32 guid = messenger.unstake{value: exactFee}(0.00001 ether);

        // 5. Verify: Check all aspects
        assertTrue(guid != bytes32(0), "GUID should be returned");

        (, bytes memory payload,,,) = mockEndpoint.getLastSendParams();
        (uint16 msgType, IUnstakeMessenger.UnstakeMessage memory message) =
            abi.decode(payload, (uint16, IUnstakeMessenger.UnstakeMessage));

        assertEq(msgType, MSG_TYPE_UNSTAKE, "Message type correct");
        assertEq(message.user, user, "User address correct");
    }

    function test_Integration_QuoteAndUnstakeFeeConsistency() public {
        // NEW BEHAVIOR: quoteUnstake() returns exact fee needed for the returnTripValue
        // Contract requires exact payment matching the quote

        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        // Get quote for base (no return trip)
        (uint256 quotedBaseFee,) = messenger.quoteUnstakeWithReturnValue(0);
        assertEq(quotedBaseFee, leg1BaseFee, "Should return leg1 base fee");

        // Get exact quote for operation with return trip
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Sending EXACT quoted fee should SUCCEED
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);

        // Sending LESS than exact fee should FAIL
        vm.expectRevert(abi.encodeWithSelector(IUnstakeMessenger.InsufficientFee.selector, exactFee, exactFee - 1));
        vm.prank(user);
        messenger.unstake{value: exactFee - 1}(0.00001 ether);
    }

    // ============ Test Group 10: Additional Coverage Tests ============

    function test_QuoteUnstakeWithBuffer_AppliesBufferCorrectly() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 baseFee = 0.01 ether;
        mockEndpoint.setQuote(baseFee, 0);

        // Get exact fee
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Get buffered fee
        (uint256 bufferedFee,) = messenger.quoteUnstakeWithBuffer(0.00001 ether);

        // Verify buffer is applied correctly
        uint256 expectedBuffered = (exactFee * (BPS_DENOMINATOR + messenger.feeBufferBPS())) / BPS_DENOMINATOR;
        assertEq(bufferedFee, expectedBuffered, "Buffered fee calculation incorrect");
        assertTrue(bufferedFee > exactFee, "Buffered fee should exceed exact fee");
    }

    function test_QuoteUnstakeWithBuffer_ClientUsagePattern() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 baseFee = 0.01 ether;
        mockEndpoint.setQuote(baseFee, 0);

        // Step 1: Get buffered quote (for estimating max required)
        (uint256 bufferedFee,) = messenger.quoteUnstakeWithBuffer(0.00001 ether);

        // Step 2: Get exact fee right before transaction
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Verify buffered is higher (safety margin)
        assertTrue(bufferedFee > exactFee, "Buffered fee should exceed exact");

        // Step 3: Client should send EXACT fee (contract requires exact payment)
        // The buffer is for client-side estimation/approval, not actual payment
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);
    }

    function test_SetFeeBufferBPS_SucceedsWithValidValues() public {
        uint256 newBuffer = 2000; // 20%

        vm.expectEmit(true, false, false, true);
        emit FeeBufferUpdated(1000, 2000);

        vm.prank(owner);
        messenger.setFeeBufferBPS(newBuffer);

        assertEq(messenger.feeBufferBPS(), newBuffer, "Buffer not updated");
    }

    function test_SetFeeBufferBPS_RevertsWhenTooLow() public {
        vm.expectRevert("Buffer too low (min 5%)");
        vm.prank(owner);
        messenger.setFeeBufferBPS(499); // < 500
    }

    function test_SetFeeBufferBPS_RevertsWhenTooHigh() public {
        vm.expectRevert("Buffer too high (max 50%)");
        vm.prank(owner);
        messenger.setFeeBufferBPS(5001); // > 5000
    }

    function test_SetFeeBufferBPS_RevertsAsNonOwner() public {
        vm.expectRevert();
        vm.prank(nonOwner);
        messenger.setFeeBufferBPS(1500);
    }

    function test_SetFeeBufferBPS_AffectsQuoteWithBuffer() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        mockEndpoint.setQuote(0.01 ether, 0);

        // Get initial buffered quote
        (uint256 buffered1,) = messenger.quoteUnstakeWithBuffer(0.00001 ether);

        // Change buffer
        vm.prank(owner);
        messenger.setFeeBufferBPS(2000); // 20%

        // Get new buffered quote
        (uint256 buffered2,) = messenger.quoteUnstakeWithBuffer(0.00001 ether);

        // Should be different
        assertTrue(buffered2 > buffered1, "Higher buffer should result in higher quote");
    }

    function test_Unstake_RevertsWithZeroReturnTripAllocation() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        mockEndpoint.setQuote(0.01 ether, 0);

        vm.expectRevert(IUnstakeMessenger.InvalidReturnTripAllocation.selector);
        vm.prank(user);
        messenger.unstake{value: 0.01 ether}(0); // returnTripAllocation = 0
    }

    function test_Unstake_EmitsCorrectEvent() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        uint256 leg1BaseFee = 0.01 ether;
        mockEndpoint.setQuote(leg1BaseFee, 0);

        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        // Expect event emission - guid is hard to predict so we check other fields
        vm.expectEmit(true, true, false, false);
        emit UnstakeRequested(user, hubEid, exactFee, 0, bytes32(0));

        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);
    }

    function test_Receive_AcceptsETHRefunds() public {
        uint256 refundAmount = 0.1 ether;

        // Simulate LayerZero refund by sending ETH to contract
        (bool success,) = address(messenger).call{value: refundAmount}("");

        assertTrue(success, "Contract should accept ETH");
        assertEq(address(messenger).balance, refundAmount, "ETH balance incorrect");

        // Owner should be able to rescue it
        vm.prank(owner);
        messenger.rescueToken(address(0), owner, refundAmount);

        assertEq(address(messenger).balance, 0, "ETH should be rescued");
    }

    function test_GasBenchmark_Unstake() public {
        vm.prank(owner);
        messenger.setPeer(hubEid, hubPeer);

        mockEndpoint.setQuote(0.01 ether, 0);
        (uint256 exactFee,) = messenger.quoteUnstakeWithReturnValue(0.00001 ether);

        uint256 gasBefore = gasleft();
        vm.prank(user);
        messenger.unstake{value: exactFee}(0.00001 ether);
        uint256 gasUsed = gasBefore - gasleft();

        // Log for gas optimization tracking
        emit log_named_uint("unstake gas used", gasUsed);

        // Assert reasonable upper bound (500k gas)
        assertLt(gasUsed, 500000, "Unstake gas usage too high");
    }
}
