// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

// Import contracts to deploy
import {iTry} from "../../../src/token/iTRY/iTry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {iTryTokenOFTAdapter} from "../../../src/token/iTRY/crosschain/iTryTokenOFTAdapter.sol";
import {iTryTokenOFT} from "../../../src/token/iTRY/crosschain/iTryTokenOFT.sol";
import {StakediTryCrosschain} from "../../../src/token/wiTRY/StakediTryCrosschain.sol";
import {wiTryVaultComposer} from "../../../src/token/wiTRY/crosschain/wiTryVaultComposer.sol";
import {UnstakeMessenger} from "../../../src/token/wiTRY/crosschain/UnstakeMessenger.sol";
import {wiTryOFTAdapter} from "../../../src/token/wiTRY/crosschain/wiTryOFTAdapter.sol";
import {wiTryOFT} from "../../../src/token/wiTRY/crosschain/wiTryOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Import LayerZero interfaces
import {IOAppCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppCore.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

abstract contract CrossChainTestBase is Test {
    // LayerZero Message Infrastructure
    struct CrossChainMessage {
        uint32 srcEid;
        bytes32 sender;
        uint32 dstEid;
        bytes32 receiver;
        bytes32 guid;
        bytes payload;
        bytes options;
        bytes composeMsg;
    }

    // Define Origin struct for LayerZero V2
    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    // Message storage and tracking
    CrossChainMessage[] public pendingMessages;
    mapping(bytes32 => bool) public processedGuids;

    // LayerZero PacketSent event signature
    bytes32 constant PACKET_SENT_SIGNATURE = keccak256("PacketSent(bytes,bytes,address)");

    // Fork identifiers
    uint256 public sepoliaForkId;
    uint256 public opSepoliaForkId;

    // Chain constants - LayerZero Endpoint IDs
    uint32 public constant SEPOLIA_EID = 40161;
    uint32 public constant OP_SEPOLIA_EID = 40232;

    // Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant OP_SEPOLIA_CHAIN_ID = 11155420;

    // LayerZero Endpoint addresses (same for both testnets)
    address public constant SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    address public constant OP_SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // RPC URLs - loaded from environment variables with fallbacks
    string public sepoliaRpcUrl;
    string public opSepoliaRpcUrl;

    // Test accounts
    address public deployer;
    address public userL1;
    address public userL2;

    // Track current chain for debugging
    string public currentChainName;

    // ============ Contract References ============

    // Sepolia (Hub/L1) contracts
    iTry public sepoliaITryToken;
    iTry public sepoliaITryImplementation;
    ERC1967Proxy public sepoliaITryProxy;
    iTryTokenOFTAdapter public sepoliaAdapter;
    StakediTryCrosschain public sepoliaVault;
    wiTryVaultComposer public sepoliaVaultComposer;
    wiTryOFTAdapter public sepoliaShareAdapter;

    // OP Sepolia (Spoke/L2) contracts
    iTryTokenOFT public opSepoliaOFT;
    wiTryOFT public opSepoliaShareOFT;
    UnstakeMessenger public opSepoliaUnstakeMessenger;

    // Modifiers for chain switching
    modifier onSepolia() {
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        _;
    }

    modifier onOpSepolia() {
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        _;
    }

    /**
     * @notice Sets up the test environment with forks for both chains
     */
    function setUp() public virtual {
        // Load RPC URLs from environment variables with fallbacks
        sepoliaRpcUrl = vm.envOr(
            "SEPOLIA_RPC_URL", string("https://eth-sepolia.g.alchemy.com/v2/WTKC-n-yAA9HA_jAR68GxbDSi4MRvzCn")
        );
        opSepoliaRpcUrl = vm.envOr(
            "OP_SEPOLIA_RPC_URL", string("https://opt-sepolia.g.alchemy.com/v2/WTKC-n-yAA9HA_jAR68GxbDSi4MRvzCn")
        );

        sepoliaForkId = vm.createFork(sepoliaRpcUrl);
        opSepoliaForkId = vm.createFork(opSepoliaRpcUrl);

        deployer = makeAddr("deployer");
        userL1 = makeAddr("userL1");
        userL2 = makeAddr("userL2");

        _fundAccountsOnBothChains();

        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
    }

    /**
     * @notice Funds test accounts on both chains
     */
    function _fundAccountsOnBothChains() private {
        vm.selectFork(sepoliaForkId);
        vm.deal(deployer, 100 ether);
        vm.deal(userL1, 100 ether);
        vm.deal(userL2, 100 ether);

        vm.selectFork(opSepoliaForkId);
        vm.deal(deployer, 100 ether);
        vm.deal(userL1, 100 ether);
        vm.deal(userL2, 100 ether);
    }

    function getCurrentChainId() public view returns (uint256) {
        return block.chainid;
    }

    function getCurrentChain() public view returns (string memory) {
        return currentChainName;
    }

    function switchToDestination(uint32 dstEid) public {
        if (dstEid == SEPOLIA_EID) {
            vm.selectFork(sepoliaForkId);
            currentChainName = "Sepolia";
        } else if (dstEid == OP_SEPOLIA_EID) {
            vm.selectFork(opSepoliaForkId);
            currentChainName = "OP Sepolia";
        } else {
            revert("Unknown destination EID");
        }
    }

    function assertCorrectChain(uint256 expectedChainId) public view {
        assertEq(block.chainid, expectedChainId, "Wrong chain");
    }

    function logChainState() public view {
        console.log("Current Chain:", currentChainName);
        console.log("Chain ID:", block.chainid);
        console.log("Fork ID:", vm.activeFork());
    }

    // ============ LayerZero Message Infrastructure ============

    /**
     * @notice Captures a LayerZero message from recorded logs
     */
    function captureMessage(uint32 srcEid, uint32 dstEid) public returns (CrossChainMessage memory message) {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        console.log("Total logs captured:", logs.length);
        console.log("Looking for srcEid:", srcEid, "dstEid:", dstEid);

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == PACKET_SENT_SIGNATURE) {
                (bytes memory encodedPayload, bytes memory options,) = abi.decode(logs[i].data, (bytes, bytes, address));

                message = _decodePacket(encodedPayload, options, srcEid, dstEid);
                if (message.srcEid == srcEid && message.dstEid == dstEid) {
                    pendingMessages.push(message);
                    console.log("Captured message from EID", message.srcEid, "to EID", message.dstEid);
                    return message;
                }
            }
        }

        revert("No matching PacketSent event found");
    }

    /**
     * @notice Decodes a LayerZero V2 packet
     */
    function _decodePacket(
        bytes memory encodedPayload,
        bytes memory options,
        uint32 expectedSrcEid,
        uint32 expectedDstEid
    ) internal pure returns (CrossChainMessage memory message) {
        uint32 _srcEid = _extractUint32(encodedPayload, 9);
        uint32 _dstEid = _extractUint32(encodedPayload, 45);

        if (_srcEid != expectedSrcEid || _dstEid != expectedDstEid) {
            return message;
        }

        message = CrossChainMessage({
            srcEid: _srcEid,
            sender: bytes32(_getSlice(encodedPayload, 13, 32)),
            dstEid: _dstEid,
            receiver: bytes32(_getSlice(encodedPayload, 49, 32)),
            guid: bytes32(_getSlice(encodedPayload, 81, 32)),
            payload: _extractPayloadFromPacket(encodedPayload),
            options: options,
            composeMsg: extractComposeMessage(options)
        });
    }

    /**
     * @notice Extracts uint32 from bytes at given offset
     */
    function _extractUint32(bytes memory data, uint256 offset) internal pure returns (uint32) {
        return (uint32(uint8(data[offset])) << 24) | (uint32(uint8(data[offset + 1])) << 16)
            | (uint32(uint8(data[offset + 2])) << 8) | uint32(uint8(data[offset + 3]));
    }

    /**
     * @notice Extracts payload from LayerZero packet
     */
    function _extractPayloadFromPacket(bytes memory encodedPayload) internal pure returns (bytes memory payload) {
        uint256 payloadOffset = 113;
        payload = new bytes(encodedPayload.length - payloadOffset);
        for (uint256 j = 0; j < payload.length; j++) {
            payload[j] = encodedPayload[payloadOffset + j];
        }
    }

    /**
     * @notice Extracts compose message from LayerZero options if present
     */
    function extractComposeMessage(bytes memory options) internal pure returns (bytes memory composeMsg) {
        if (options.length == 0) return composeMsg;

        uint256 offset = 0;
        while (offset < options.length) {
            uint8 optionType = uint8(options[offset]);
            offset += 1;

            if (optionType == 3) {
                uint16 msgLength;
                assembly {
                    msgLength := mload(add(add(options, 0x20), offset))
                }
                offset += 18; // Skip msgLength(2) + gas(8) + value(8)

                composeMsg = new bytes(msgLength);
                for (uint256 i = 0; i < msgLength; i++) {
                    composeMsg[i] = options[offset + i];
                }
                break;
            } else if (optionType == 1) {
                offset += 18; // Skip length(2) + gas(8) + value(8)
            } else {
                break;
            }
        }

        return composeMsg;
    }

    function clearPendingMessages() public {
        delete pendingMessages;
    }

    function getPendingMessageCount() public view returns (uint256) {
        return pendingMessages.length;
    }

    function captureAndRelay(uint32 srcEid, uint32 dstEid) public returns (CrossChainMessage memory message) {
        message = captureMessage(srcEid, dstEid);
        relayMessage(message);
        return message;
    }

    function getGuid(CrossChainMessage memory message) internal pure returns (bytes32) {
        return keccak256(abi.encode(message.srcEid, message.sender, message.dstEid, message.guid));
    }

    function getEndpointByEid(uint32 eid) internal pure returns (address) {
        if (eid == SEPOLIA_EID) return SEPOLIA_ENDPOINT;
        if (eid == OP_SEPOLIA_EID) return OP_SEPOLIA_ENDPOINT;
        revert("Unknown EID");
    }

    function extractPayload(bytes memory fullPayload) internal pure returns (bytes memory) {
        return fullPayload;
    }

    /**
     * @notice Manually relays a captured message to the destination chain
     */
    function relayMessage(CrossChainMessage memory message) internal {
        console.log("Relaying message from EID", message.srcEid, "to EID", message.dstEid);

        bytes32 guid = getGuid(message);
        require(!processedGuids[guid], "Message already processed");

        switchToDestination(message.dstEid);

        _callLzReceive(message);

        processedGuids[guid] = true;
        console.log("Message relayed successfully");

        _handleCompose(message);
    }

    /**
     * @notice Calls lzReceive on the destination OApp
     */
    function _callLzReceive(CrossChainMessage memory message) internal {
        address dstEndpoint = getEndpointByEid(message.dstEid);
        address receiver = address(uint160(uint256(message.receiver)));

        console.log("Calling lzReceive on receiver:", receiver);
        vm.prank(dstEndpoint);

        (bool success, bytes memory returnData) = receiver.call(
            abi.encodeWithSignature(
                "lzReceive((uint32,bytes32,uint64),bytes32,bytes,address,bytes)",
                Origin(message.srcEid, message.sender, extractNonce(message)),
                message.guid,
                extractPayload(message.payload),
                address(this),
                ""
            )
        );

        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert("lzReceive failed without reason");
            }
        }
    }

    /**
     * @notice Handles compose callback if present
     */
    function _handleCompose(CrossChainMessage memory message) internal {
        bytes32 COMPOSE_SENT_SIGNATURE = keccak256("ComposeSent(address,address,bytes32,uint16,bytes)");

        Vm.Log[] memory composeLogs = vm.getRecordedLogs();
        for (uint256 i = 0; i < composeLogs.length; i++) {
            if (composeLogs[i].topics[0] == COMPOSE_SENT_SIGNATURE) {
                console.log("ComposeSent event detected, calling lzCompose...");

                (, address composeTo,,, bytes memory composeMessage) =
                    abi.decode(composeLogs[i].data, (address, address, bytes32, uint16, bytes));

                _callLzCompose(message, composeTo, composeMessage);
                break;
            }
        }
    }

    /**
     * @notice Calls lzCompose on the composer contract
     */
    function _callLzCompose(CrossChainMessage memory message, address composeTo, bytes memory composeMessage) internal {
        address dstEndpoint = getEndpointByEid(message.dstEid);
        address receiver = address(uint160(uint256(message.receiver)));

        vm.prank(dstEndpoint);
        (bool success, bytes memory returnData) = composeTo.call(
            abi.encodeWithSignature(
                "lzCompose(address,bytes32,bytes,address,bytes)",
                receiver,
                message.guid,
                composeMessage,
                address(this),
                ""
            )
        );

        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert("lzCompose failed without reason");
            }
        }

        console.log("lzCompose called successfully");
    }

    function extractNonce(CrossChainMessage memory message) internal pure returns (uint64) {
        return uint64(uint256(message.guid >> 192));
    }

    function _getSlice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    // ============ Contract Deployment Functions ============

    function deploySepoliaContracts() public onSepolia {
        vm.startPrank(deployer);

        // Deploy iTry with proxy pattern
        sepoliaITryImplementation = new iTry();
        bytes memory initData = abi.encodeWithSelector(iTry.initialize.selector, deployer, deployer);
        sepoliaITryProxy = new ERC1967Proxy(address(sepoliaITryImplementation), initData);
        sepoliaITryToken = iTry(address(sepoliaITryProxy));
        console.log("Deployed iTry on Sepolia:", address(sepoliaITryToken));

        sepoliaAdapter = new iTryTokenOFTAdapter(address(sepoliaITryToken), SEPOLIA_ENDPOINT, deployer);
        console.log("Deployed iTryTokenOFTAdapter on Sepolia:", address(sepoliaAdapter));

        sepoliaVault = new StakediTryCrosschain(
            IERC20(address(sepoliaITryToken)),
            deployer, // rewarder
            deployer, // owner
            deployer // treasury for fast redeem
        );
        console.log("Deployed StakediTryCrosschain vault on Sepolia:", address(sepoliaVault));

        sepoliaShareAdapter = new wiTryOFTAdapter(address(sepoliaVault), SEPOLIA_ENDPOINT, deployer);
        console.log("Deployed wiTryOFTAdapter on Sepolia:", address(sepoliaShareAdapter));

        // Deploy wiTryVaultComposer
        sepoliaVaultComposer = new wiTryVaultComposer(
            address(sepoliaVault), address(sepoliaAdapter), address(sepoliaShareAdapter), SEPOLIA_ENDPOINT
        );
        console.log("Deployed wiTryVaultComposer on Sepolia:", address(sepoliaVaultComposer));

        // Grant COMPOSER_ROLE to wiTryVaultComposer
        bytes32 COMPOSER_ROLE = sepoliaVault.COMPOSER_ROLE();
        sepoliaVault.grantRole(COMPOSER_ROLE, address(sepoliaVaultComposer));
        console.log("Granted COMPOSER_ROLE to wiTryVaultComposer");

        vm.stopPrank();
    }

    function deployOpSepoliaContracts() public onOpSepolia {
        vm.startPrank(deployer);

        opSepoliaOFT = new iTryTokenOFT(OP_SEPOLIA_ENDPOINT, deployer);
        console.log("Deployed iTryTokenOFT on OP Sepolia:", address(opSepoliaOFT));

        opSepoliaShareOFT = new wiTryOFT("wiTRY", "wiTRY", OP_SEPOLIA_ENDPOINT, deployer);
        console.log("Deployed wiTryOFT on OP Sepolia:", address(opSepoliaShareOFT));

        // Deploy UnstakeMessenger
        opSepoliaUnstakeMessenger = new UnstakeMessenger(
            OP_SEPOLIA_ENDPOINT,
            deployer,
            SEPOLIA_EID // hubEid
        );
        console.log("Deployed UnstakeMessenger on OP Sepolia:", address(opSepoliaUnstakeMessenger));

        vm.stopPrank();
    }

    function configurePeers() public {
        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        vm.prank(deployer);
        IOAppCore(address(sepoliaAdapter)).setPeer(OP_SEPOLIA_EID, bytes32(uint256(uint160(address(opSepoliaOFT)))));
        console.log("Set peer: Sepolia Adapter -> OP Sepolia OFT");

        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        vm.prank(deployer);
        IOAppCore(address(opSepoliaOFT)).setPeer(SEPOLIA_EID, bytes32(uint256(uint160(address(sepoliaAdapter)))));
        console.log("Set peer: OP Sepolia OFT -> Sepolia Adapter");

        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        vm.prank(deployer);
        IOAppCore(address(sepoliaShareAdapter))
            .setPeer(OP_SEPOLIA_EID, bytes32(uint256(uint160(address(opSepoliaShareOFT)))));
        console.log("Set peer: Sepolia Share Adapter -> OP Sepolia Share OFT");

        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        vm.prank(deployer);
        IOAppCore(address(opSepoliaShareOFT))
            .setPeer(SEPOLIA_EID, bytes32(uint256(uint160(address(sepoliaShareAdapter)))));
        console.log("Set peer: OP Sepolia Share OFT -> Sepolia Share Adapter");

        // Configure UnstakeMessenger ↔ wiTryVaultComposer peers
        vm.selectFork(opSepoliaForkId);
        currentChainName = "OP Sepolia";
        vm.prank(deployer);
        IOAppCore(address(opSepoliaUnstakeMessenger))
            .setPeer(SEPOLIA_EID, bytes32(uint256(uint160(address(sepoliaVaultComposer)))));
        console.log("Set peer: OP Sepolia UnstakeMessenger -> Sepolia VaultComposer");

        vm.selectFork(sepoliaForkId);
        currentChainName = "Sepolia";
        vm.prank(deployer);
        IOAppCore(address(sepoliaVaultComposer))
            .setPeer(OP_SEPOLIA_EID, bytes32(uint256(uint160(address(opSepoliaUnstakeMessenger)))));
        console.log("Set peer: Sepolia VaultComposer -> OP Sepolia UnstakeMessenger");
    }

    function deployAllContracts() public {
        console.log("\n=== Deploying Sepolia Contracts ===");
        deploySepoliaContracts();

        console.log("\n=== Deploying OP Sepolia Contracts ===");
        deployOpSepoliaContracts();

        console.log("\n=== Configuring Peers ===");
        configurePeers();

        console.log("\n=== Deployment Complete ===");
        logDeployedContracts();
    }

    function logDeployedContracts() public view {
        console.log("\nSepolia Contracts:");
        console.log("  iTry:", address(sepoliaITryToken));
        console.log("  iTryTokenOFTAdapter:", address(sepoliaAdapter));
        console.log("  StakediTry (wiTRY):", address(sepoliaVault));
        console.log("  wiTryOFTAdapter:", address(sepoliaShareAdapter));

        console.log("\nOP Sepolia Contracts:");
        console.log("  iTryTokenOFT:", address(opSepoliaOFT));
        console.log("  wiTryOFT:", address(opSepoliaShareOFT));
    }

    function verifyPeerConfiguration() public {
        console.log("\n=== Verifying Peer Configuration ===");

        vm.selectFork(sepoliaForkId);
        assertEq(
            IOAppCore(address(sepoliaAdapter)).peers(OP_SEPOLIA_EID),
            bytes32(uint256(uint160(address(opSepoliaOFT)))),
            "Sepolia adapter peer mismatch"
        );

        vm.selectFork(opSepoliaForkId);
        assertEq(
            IOAppCore(address(opSepoliaOFT)).peers(SEPOLIA_EID),
            bytes32(uint256(uint160(address(sepoliaAdapter)))),
            "OP Sepolia OFT peer mismatch"
        );

        vm.selectFork(sepoliaForkId);
        assertEq(
            IOAppCore(address(sepoliaShareAdapter)).peers(OP_SEPOLIA_EID),
            bytes32(uint256(uint160(address(opSepoliaShareOFT)))),
            "Sepolia share adapter peer mismatch"
        );

        vm.selectFork(opSepoliaForkId);
        assertEq(
            IOAppCore(address(opSepoliaShareOFT)).peers(SEPOLIA_EID),
            bytes32(uint256(uint160(address(sepoliaShareAdapter)))),
            "OP Sepolia share OFT peer mismatch"
        );

        console.log("\nAll peer configurations verified");
    }

    function mintITry(address to, uint256 amount) public onSepolia {
        vm.prank(deployer);
        sepoliaITryToken.mint(to, amount);
    }

    // ============ Test Utility Functions ============

    function estimateGas(address oft, SendParam memory sendParam)
        internal
        returns (uint256 nativeFee, uint256 lzTokenFee)
    {
        (bool success, bytes memory data) = oft.call(
            abi.encodeWithSignature(
                "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)", sendParam, false
            )
        );

        require(success, "quoteSend failed");
        (nativeFee, lzTokenFee) = abi.decode(data, (uint256, uint256));
    }

    function assertMessageProcessed(bytes32 guid) internal {
        assertTrue(processedGuids[guid], "Message not processed");
    }

    function getTotalSupply() internal returns (uint256 l1Supply, uint256 l2Supply, uint256 total) {
        vm.selectFork(sepoliaForkId);
        l1Supply = sepoliaITryToken.totalSupply();

        vm.selectFork(opSepoliaForkId);
        l2Supply = opSepoliaOFT.totalSupply();

        total = l1Supply + l2Supply;
    }

    function logChainState(string memory label) internal {
        console.log("\n=== Chain State:", label, "===");

        uint256 currentFork = vm.activeFork();

        vm.selectFork(sepoliaForkId);
        console.log("Sepolia (L1):");
        console.log("  iTRY Total Supply:", sepoliaITryToken.totalSupply());
        if (address(sepoliaAdapter) != address(0)) {
            console.log("  iTRY Locked in Adapter:", sepoliaITryToken.balanceOf(address(sepoliaAdapter)));
        }
        if (address(sepoliaVault) != address(0)) {
            console.log("  Vault Total Assets:", sepoliaVault.totalAssets());
            console.log("  Vault Total Supply (shares):", sepoliaVault.totalSupply());
            if (address(sepoliaShareAdapter) != address(0)) {
                console.log("  Shares Locked in Adapter:", sepoliaVault.balanceOf(address(sepoliaShareAdapter)));
            }
        }

        vm.selectFork(opSepoliaForkId);
        console.log("OP Sepolia (L2):");
        if (address(opSepoliaOFT) != address(0)) {
            console.log("  iTRY OFT Supply:", opSepoliaOFT.totalSupply());
        }
        if (address(opSepoliaShareOFT) != address(0)) {
            console.log("  Share OFT Supply:", opSepoliaShareOFT.totalSupply());
        }

        console.log("========================\n");

        vm.selectFork(currentFork);
    }
}
