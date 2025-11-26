// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {KeyDerivation} from "../../utils/KeyDerivation.sol";

// wiTryVaultComposer interface
interface IVaultComposer {
    function depositAndSend(
        uint256 _assetAmount,
        SendParam memory _sendParam,
        address _refundAddress
    ) external payable;

    function VAULT() external view returns (address);
    function ASSET_ERC20() external view returns (address);
    function SHARE_OFT() external view returns (address);
}

// OFT interface for fee quote
interface IOFT {
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
        external view returns (MessagingFee memory msgFee);
}

/**
 * @title StakeAndBridgeWITRY_HubToSpoke_RedeemerAddress
 * @notice Stake iTRY into composer and bridge wiTRY shares to spoke chain in one transaction
 * @dev Usage:
 *   STAKE_AMOUNT=50000000000000000000 forge script script/test/composer/StakeAndBridgeWITRY_HubToSpoke_RedeemerAddress.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
 *
 * Environment Variables:
 *   - DEPLOYER_PRIVATE_KEY: Master key for deriving redeemer key
 *   - STAKE_AMOUNT: Amount in wei (e.g., 50e18 = 50000000000000000000)
 *   - VAULT_COMPOSER: wiTryVaultComposer address on hub chain (Sepolia)
 *   - SPOKE_CHAIN_EID: LayerZero endpoint ID for spoke chain (OP Sepolia)
 *
 * Alternatively, you can use the REDEEMER_KEY environment variable directly:
 *   - REDEEMER_KEY: Redeemer's private key
 */
contract StakeAndBridgeWITRY_HubToSpoke_RedeemerAddress is Script {
    using OptionsBuilder for bytes;

    function run() public {
        require(block.chainid == 11155111, "Must run on Sepolia (Hub Chain)");

        // Read environment variables
        uint256 redeemerKey;

        // Try to get REDEEMER_KEY directly, otherwise derive from DEPLOYER_PRIVATE_KEY
        try vm.envUint("REDEEMER_KEY") returns (uint256 key) {
            redeemerKey = key;
            console2.log("Using REDEEMER_KEY from environment");
        } catch {
            uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
            KeyDerivation.ActorKeys memory keys = KeyDerivation.getActorKeys(vm, deployerKey);
            redeemerKey = keys.redeemer;
            console2.log("Derived redeemer key from DEPLOYER_PRIVATE_KEY");
        }

        address redeemerAddress = vm.addr(redeemerKey);
        uint256 stakeAmount = vm.envUint("STAKE_AMOUNT");
        address vaultComposer = vm.envAddress("VAULT_COMPOSER");
        uint32 spokeEid = uint32(vm.envUint("SPOKE_CHAIN_EID"));

        console2.log("========================================");
        console2.log("STAKE & BRIDGE wiTRY: HUB TO SPOKE - REDEEMER");
        console2.log("========================================");
        console2.log("Direction: Hub (Sepolia) -> Spoke (OP Sepolia)");
        console2.log("Operation: Stake iTRY + Bridge wiTRY Shares");
        console2.log("Redeemer address:", redeemerAddress);
        console2.log("wiTryVaultComposer:", vaultComposer);
        console2.log("Destination EID:", spokeEid);
        console2.log("Stake Amount:", stakeAmount / 1e18, "iTRY");
        console2.log("=========================================\n");

        // Get contract addresses from wiTryVaultComposer
        IVaultComposer composer = IVaultComposer(vaultComposer);
        address itryToken = composer.ASSET_ERC20();
        address staking = composer.VAULT();
        address shareOFT = composer.SHARE_OFT();

        console2.log("iTRY Token:", itryToken);
        console2.log("StakediTryCrosschain:", staking);
        console2.log("wiTRY OFT Adapter:", shareOFT);
        console2.log("");

        // Check redeemer iTRY balance
        uint256 itryBalance = IERC20(itryToken).balanceOf(redeemerAddress);
        console2.log("Redeemer iTRY balance on Hub:", itryBalance / 1e18, "iTRY");
        require(itryBalance >= stakeAmount, "Redeemer has insufficient iTRY balance");

        // Estimate shares that will be minted
        uint256 estimatedShares = IERC4626(staking).previewDeposit(stakeAmount);
        console2.log("Estimated wiTRY shares:", estimatedShares / 1e18, "wiTRY\n");

        // Build LayerZero options - 200k gas for lzReceive
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        // Build SendParam - shares will be sent to redeemer on spoke chain
        SendParam memory sendParam = SendParam({
            dstEid: spokeEid,
            to: bytes32(uint256(uint160(redeemerAddress))),
            amountLD: estimatedShares,
            minAmountLD: estimatedShares,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        // Get fee quote from share OFT
        MessagingFee memory fee = IOFT(shareOFT).quoteSend(sendParam, false);
        console2.log("LayerZero fee:", fee.nativeFee / 1e15, "finney");
        console2.log("Estimated total cost:", fee.nativeFee / 1e18, "ETH\n");

        // Check ETH balance for fee
        uint256 ethBalance = redeemerAddress.balance;
        console2.log("Redeemer ETH balance:", ethBalance / 1e18, "ETH");
        require(ethBalance >= fee.nativeFee, "Insufficient ETH for LayerZero fee");

        vm.startBroadcast(redeemerKey);

        // Approve if needed
        uint256 allowance = IERC20(itryToken).allowance(redeemerAddress, vaultComposer);
        if (allowance < stakeAmount) {
            console2.log("Approving iTRY transfer...");
            IERC20(itryToken).approve(vaultComposer, type(uint256).max);
        }

        // Execute depositAndSend - stakes iTRY and bridges wiTRY in one transaction
        console2.log("Executing depositAndSend...");
        console2.log("  1. Staking", stakeAmount / 1e18, "iTRY into vault");
        console2.log("  2. Minting ~", estimatedShares / 1e18, "wiTRY shares");
        console2.log("  3. Bridging shares to OP Sepolia\n");

        composer.depositAndSend{value: fee.nativeFee}(
            stakeAmount,
            sendParam,
            redeemerAddress // refund address
        );

        vm.stopBroadcast();

        console2.log("\n========================================");
        console2.log("[OK] Stake & Bridge transaction sent!");
        console2.log("Redeemer will receive ~", estimatedShares / 1e18, "wiTRY on OP Sepolia");
        console2.log("Track your transaction at:");
        console2.log("https://testnet.layerzeroscan.com/");
        console2.log("========================================");
    }
}
