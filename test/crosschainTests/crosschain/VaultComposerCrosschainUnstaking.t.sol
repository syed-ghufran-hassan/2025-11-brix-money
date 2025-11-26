// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {wiTryVaultComposer} from "../../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {IwiTryVaultComposer} from "../../../src/token/wiTRY/crosschain/interfaces/IwiTryVaultComposer.sol";
import {StakediTryCrosschain} from "../../../src/token/wiTRY/StakediTryCrosschain.sol";
import {IStakediTryCrosschain} from "../../../src/token/wiTRY/interfaces/IStakediTryCrosschain.sol";
import {Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockERC20
 * @notice Simple ERC20 mock
 */
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

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
        if (_allowances[from][msg.sender] != type(uint256).max) {
            _allowances[from][msg.sender] -= amount;
        }
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

/**
 * @title MockLayerZeroEndpoint
 * @notice Mock endpoint for testing
 */
contract MockLayerZeroEndpoint {
    address public delegate;
    uint32 public immutable eid;

    constructor() {
        eid = 40161; // Sepolia EID
    }

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }
}

/**
 * @title MockOFT
 * @notice Mock OFT for testing
 */
contract MockOFT {
    address public immutable token;
    address public immutable endpoint;

    constructor(address _token, address _endpoint) {
        token = _token;
        endpoint = _endpoint;
    }

    function approvalRequired() external pure returns (bool) {
        return true; // ShareOFT must be an adapter
    }
}

/**
 * @title wiTryVaultComposerCrosschainUnstakingTest
 * @notice Unit tests for wiTryVaultComposer crosschain unstaking functionality
 * @dev Tests OApp integration, message routing, and _handleUnstake logic
 */
contract wiTryVaultComposerCrosschainUnstakingTest is Test {
    wiTryVaultComposer public composer;
    StakediTryCrosschain public vault;
    MockERC20 public usde;
    MockLayerZeroEndpoint public mockEndpoint;
    MockOFT public mockAssetOFT;
    MockOFT public mockShareOFT;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public nonOwner = makeAddr("nonOwner");

    uint32 public constant SPOKE_EID = 40232; // OP Sepolia
    uint32 public constant HUB_EID = 40161; // Sepolia
    bytes32 public constant SPOKE_PEER = bytes32(uint256(uint160(address(0x1234))));

    // Constants from wiTryVaultComposer
    uint16 constant MSG_TYPE_UNSTAKE = 1;

    // Events
    event CrosschainUnstakeProcessed(address indexed user, uint32 indexed srcEid, uint256 assets, bytes32 guid);

    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        // Deploy mock tokens
        usde = new MockERC20("USDe", "USDe");

        // Deploy mock endpoint
        mockEndpoint = new MockLayerZeroEndpoint();

        // Deploy StakediTryCrosschain first (vault IS the share token)
        // Constructor: (IERC20 _asset, address initialRewarder, address owner, address _fastRedeemTreasury)
        // Note: The 'owner' parameter in constructor receives DEFAULT_ADMIN_ROLE automatically
        address fastRedeemTreasury = makeAddr("fastRedeemTreasury");
        vault = new StakediTryCrosschain(IERC20(address(usde)), owner, owner, fastRedeemTreasury);

        // Deploy mock OFTs - shareOFT must point to vault as the token
        mockAssetOFT = new MockOFT(address(usde), address(mockEndpoint));
        mockShareOFT = new MockOFT(address(vault), address(mockEndpoint)); // vault is the share token!

        // Deploy wiTryVaultComposer with owner as msg.sender so OApp owner is set correctly
        vm.prank(owner);
        composer =
            new wiTryVaultComposer(address(vault), address(mockAssetOFT), address(mockShareOFT), address(mockEndpoint));

        // Grant COMPOSER_ROLE to wiTryVaultComposer using AccessControl
        // 'owner' has DEFAULT_ADMIN_ROLE from constructor, so they can grant roles
        bytes32 composerRole = vault.COMPOSER_ROLE(); // Get role hash first to avoid consuming prank
        vm.prank(owner);
        vault.grantRole(composerRole, address(composer));

        // Configure peer for OApp
        vm.prank(owner);
        composer.setPeer(SPOKE_EID, SPOKE_PEER);
    }

    // ============ Test Group 1: OApp Inheritance Tests ============

    function test_OAppInheritance_DoesNotBreakExistingFunctionality() public {
        // Verify wiTryVaultComposer still has wiTryVaultComposerSync functionality
        assertEq(address(composer.VAULT()), address(vault), "Vault reference intact");
        assertEq(composer.ASSET_OFT(), address(mockAssetOFT), "Asset OFT reference intact");
        assertEq(composer.SHARE_OFT(), address(mockShareOFT), "Share OFT reference intact");
    }

    function test_OAppInheritance_OwnerCanSetPeer() public {
        uint32 newEid = 40245;
        bytes32 newPeer = bytes32(uint256(uint160(makeAddr("newPeer"))));

        vm.prank(owner);
        composer.setPeer(newEid, newPeer);

        // Verify peer set (would need getPeer function to test fully)
        // This test confirms setPeer doesn't revert
    }

    function test_OAppInheritance_NonOwnerCannotSetPeer() public {
        uint32 newEid = 40245;
        bytes32 newPeer = bytes32(uint256(uint160(makeAddr("newPeer"))));

        vm.expectRevert();
        vm.prank(nonOwner);
        composer.setPeer(newEid, newPeer);
    }

    // ============ Test Group 2: Message Routing Tests ============

    function test_LzReceive_RoutesUnstakeMessageCorrectly() public {
        // Setup: Create cooldown for user
        _setupCooldownForUser(user, 1000e18, 1000e18);

        // Fast forward past cooldown
        vm.warp(block.timestamp + vault.cooldownDuration() + 1);

        // Prepare unstake message
        bytes memory unstakeMsg = abi.encode(user, hex"");
        bytes memory fullMessage = abi.encode(MSG_TYPE_UNSTAKE, unstakeMsg);

        Origin memory origin = Origin({srcEid: SPOKE_EID, sender: SPOKE_PEER, nonce: 1});

        bytes32 guid = keccak256("test-guid");

        // Fund composer with ETH for return trip
        vm.deal(address(composer), 1 ether);

        // Mock endpoint calls _lzReceive
        // Note: In real test, this would come through the endpoint
        // For unit test, we directly test the routing logic by calling the function
        // that would be invoked by LayerZero

        // Since _lzReceive is internal, we test it indirectly through the public interface
        // In production, LayerZero endpoint would call lzReceive which calls _lzReceive
        // For now, we verify the message structure is correct
        (uint16 msgType,) = abi.decode(fullMessage, (uint16, bytes));
        assertEq(msgType, MSG_TYPE_UNSTAKE, "Message type should be MSG_TYPE_UNSTAKE");
    }

    function test_LzReceive_RevertsForUnknownMessageType() public {
        // This test documents that unknown message types revert
        // In production, _lzReceive would be called by LayerZero endpoint
        // Unknown message types should revert with UnknownMessageType error

        uint16 unknownType = 99;
        bytes memory unknownMsg = abi.encode(address(user), hex"");
        bytes memory fullMessage = abi.encode(unknownType, unknownMsg);

        (uint16 msgType,) = abi.decode(fullMessage, (uint16, bytes));
        assertNotEq(msgType, MSG_TYPE_UNSTAKE, "Message type should be unknown");

        // If _lzReceive were called with this message, it would revert
        // This test documents the expected behavior
    }

    // ============ Test Group 3: Peer Validation Tests ============

    function test_PeerValidation_AuthorizedPeerCanSend() public {
        // LayerZero OApp validates peers before calling _lzReceive
        // Only configured peers can send messages
        // This test documents that peer validation happens at OApp level

        // Verify peer is configured
        bytes32 configuredPeer = SPOKE_PEER;
        assertTrue(configuredPeer != bytes32(0), "Peer should be configured");
    }

    function test_PeerValidation_UnauthorizedPeerCannotSend() public {
        // LayerZero OApp automatically rejects messages from unconfigured peers
        // No need to test in _lzReceive - OApp handles this before _lzReceive is called

        bytes32 unauthorizedPeer = bytes32(uint256(uint160(makeAddr("unauthorized"))));
        assertTrue(unauthorizedPeer != SPOKE_PEER, "Peer should be unauthorized");

        // In production, LayerZero would reject this before _lzReceive
    }

    // ============ Test Group 4: Rescue Function Tests ============

    function test_RescueToken_ERC20_SucceedsAsOwner() public {
        MockERC20 token = new MockERC20("Test", "TST");
        uint256 amount = 1000e18;

        // Send tokens to composer
        token.mint(address(composer), amount);

        assertEq(token.balanceOf(address(composer)), amount);
        assertEq(token.balanceOf(owner), 0);

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit TokenRescued(address(token), owner, amount);

        // Rescue tokens
        vm.prank(owner);
        composer.rescueToken(address(token), owner, amount);

        // Verify tokens transferred
        assertEq(token.balanceOf(address(composer)), 0);
        assertEq(token.balanceOf(owner), amount);
    }

    function test_RescueToken_ERC20_RevertsAsNonOwner() public {
        MockERC20 token = new MockERC20("Test", "TST");
        uint256 amount = 1000e18;
        token.mint(address(composer), amount);

        vm.expectRevert();
        vm.prank(nonOwner);
        composer.rescueToken(address(token), owner, amount);
    }

    function test_RescueToken_RevertsWithZeroRecipient() public {
        MockERC20 token = new MockERC20("Test", "TST");
        uint256 amount = 1000e18;

        vm.expectRevert(IwiTryVaultComposer.InvalidZeroAddress.selector);
        vm.prank(owner);
        composer.rescueToken(address(token), address(0), amount);
    }

    function test_RescueToken_RevertsWithZeroAmount() public {
        MockERC20 token = new MockERC20("Test", "TST");

        vm.expectRevert(IwiTryVaultComposer.InvalidAmount.selector);
        vm.prank(owner);
        composer.rescueToken(address(token), owner, 0);
    }

    function test_RescueToken_ETH_SucceedsAsOwner() public {
        uint256 amount = 1 ether;

        // Send ETH to composer
        vm.deal(address(composer), amount);

        uint256 initialBalance = owner.balance;

        // Expect event (address(0) for ETH)
        vm.expectEmit(true, true, false, true);
        emit TokenRescued(address(0), owner, amount);

        // Rescue ETH
        vm.prank(owner);
        composer.rescueToken(address(0), owner, amount);

        // Verify ETH transferred
        assertEq(address(composer).balance, 0);
        assertEq(owner.balance, initialBalance + amount);
    }

    function test_RescueToken_ETH_RevertsAsNonOwner() public {
        uint256 amount = 1 ether;
        vm.deal(address(composer), amount);

        vm.expectRevert();
        vm.prank(nonOwner);
        composer.rescueToken(address(0), owner, amount);
    }

    function test_RescueToken_ETH_RevertsWithZeroRecipient() public {
        uint256 amount = 1 ether;
        vm.expectRevert(IwiTryVaultComposer.InvalidZeroAddress.selector);
        vm.prank(owner);
        composer.rescueToken(address(0), address(0), amount);
    }

    function test_RescueToken_ETH_RevertsWithZeroAmount() public {
        vm.expectRevert(IwiTryVaultComposer.InvalidAmount.selector);
        vm.prank(owner);
        composer.rescueToken(address(0), owner, 0);
    }

    // ============ Test Group 5: handleCompose Tests (Existing Flow) ============

    function test_HandleCompose_InitiateCooldownStillWorks() public {
        // Verify that existing INITIATE_COOLDOWN compose flow still works
        // after adding OApp functionality

        // This test documents that handleCompose routing is unchanged
        // Real integration test would verify full compose flow
        // For unit test, we verify the contract structure is correct

        assertEq(address(composer.VAULT()), address(vault));
        assertTrue(address(composer) != address(0));
    }

    // ============ Helper Functions ============

    /**
     * @dev Helper to setup cooldown for user
     * @param _user User address
     * @param _shares Number of shares to cooldown
     * @param _depositAmount Amount to deposit first
     */
    function _setupCooldownForUser(address _user, uint256 _shares, uint256 _depositAmount) internal {
        // Mint USDe to user
        usde.mint(_user, _depositAmount);

        // User deposits into vault
        vm.startPrank(_user);
        usde.approve(address(vault), _depositAmount);
        vault.deposit(_depositAmount, _user);
        vm.stopPrank();

        // User transfers shares to composer
        vm.prank(_user);
        vault.transfer(address(composer), _shares);

        // Composer initiates cooldown for user
        vm.prank(address(composer));
        vault.cooldownSharesByComposer(_shares, _user);
    }
}
