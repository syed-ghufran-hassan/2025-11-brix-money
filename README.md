

# Scope

*See [scope.txt](https://github.com/code-423n4/2025-11-brix-money/blob/main/scope.txt)*

### Files in scope


| File   | Logic Contracts | Interfaces | nSLOC | Purpose | Libraries used |
| ------ | --------------- | ---------- | ----- | -----   | ------------ |
| /src/protocol/FastAccessVault.sol | 1| **** | 118 | |@openzeppelin/contracts/access/Ownable.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| /src/protocol/YieldForwarder.sol | 1| **** | 50 | |@openzeppelin/contracts/access/Ownable.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| /src/protocol/iTryIssuer.sol | 1| **** | 286 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/iTRY/crosschain/iTryTokenOFT.sol | 1| **** | 87 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/iTRY/crosschain/iTryTokenOFTAdapter.sol | 1| **** | 5 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol|
| /src/token/iTRY/iTry.sol | 1| **** | 128 | |@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol<br>@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol<br>@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol<br>@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol|
| /src/token/wiTRY/StakediTry.sol | 1| **** | 141 | |@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol|
| /src/token/wiTRY/StakediTryCooldown.sol | 1| **** | 62 | ||
| /src/token/wiTRY/StakediTryCrosschain.sol | 1| **** | 65 | |@openzeppelin/contracts/token/ERC20/IERC20.sol|
| /src/token/wiTRY/StakediTryFastRedeem.sol | 1| **** | 67 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| /src/token/wiTRY/crosschain/UnstakeMessenger.sol | 1| **** | 108 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol<br>@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/wiTRY/crosschain/wiTryOFT.sol | 1| **** | 45 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol|
| /src/token/wiTRY/crosschain/wiTryOFTAdapter.sol | 1| **** | 5 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol|
| /src/token/wiTRY/crosschain/wiTryVaultComposer.sol | 1| **** | 144 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| /src/token/wiTRY/iTrySilo.sol | 1| **** | 20 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| **Totals** | **15** | **** | **1331** | | |

### Files out of scope

*See [out_of_scope.txt](https://github.com/code-423n4/2025-11-brix-money/blob/main/out_of_scope.txt)*

| File         |
| ------------ |
| ./script/config/01_ConfigurePeers.s.sol |
| ./script/config/02_SetLibraries.s.sol |
| ./script/config/03_SetEnforcedOptionsShareAdapter.s.sol |
| ./script/config/04_SetEnforcedOptionsShareOFT.s.sol |
| ./script/config/06_SetEnforcedOptionsiTryAdapter.s.sol |
| ./script/deploy/DeploymentRegistry.sol |
| ./script/deploy/hub/01_DeployCore.s.sol |
| ./script/deploy/hub/02_DeployProtocol.s.sol |
| ./script/deploy/hub/03_DeployCrossChain.s.sol |
| ./script/deploy/hub/04_SetupTestnetState.s.sol |
| ./script/deploy/spoke/SpokeChainDeployment.s.sol |
| ./script/old/10_DeployCore.s.sol |
| ./script/old/11_DeployProtocol.s.sol |
| ./script/old/12_DeployCrossChain.s.sol |
| ./script/old/13_SetupTestnetState.s.sol |
| ./script/old/20_DeploySpoke.s.sol |
| ./script/old/30_ConfigurePeers.s.sol |
| ./script/old/32_ConfigureLZLibraries.s.sol |
| ./script/old/40_VerifyHub.s.sol |
| ./script/old/DeploymentRegistry.sol |
| ./script/old/KeyDerivation.sol |
| ./script/test/bridge/BridgeITRY_HubToSpoke_RedeemerAddress.s.sol |
| ./script/test/bridge/BridgeITRY_SpokeToHub_RedeemerAddress.s.sol |
| ./script/test/bridge/BridgeWITRY_HubToSpoke_Staker1.s.sol |
| ./script/test/bridge/BridgeWITRY_SpokeToHub_Staker1.s.sol |
| ./script/test/composer/BridgeAndInitiateCooldown_SpokeToHub_RedeemerAddress.s.sol |
| ./script/test/composer/BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress.s.sol |
| ./script/test/composer/CrosschainUnstake_SpokeToHubToSpoke_RedeemerAddress.s.sol |
| ./script/test/composer/FastRedeemAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress.s.sol |
| ./script/test/composer/InitiateCooldownRefund_SpokeToHub_RedeemerAddress.s.sol |
| ./script/test/composer/StakeAndBridgeWITRY_HubToSpoke_RedeemerAddress.s.sol |
| ./script/utils/KeyDerivation.sol |
| ./src/external/DLFToken.sol |
| ./src/protocol/RedstoneNAVFeed.sol |
| ./src/protocol/interfaces/IFastAccessVault.sol |
| ./src/protocol/interfaces/IiTryIssuer.sol |
| ./src/protocol/periphery/CommonErrors.sol |
| ./src/protocol/periphery/IOracle.sol |
| ./src/protocol/periphery/IYieldProcessor.sol |
| ./src/token/iTRY/IiTryDefinitions.sol |
| ./src/token/iTRY/interfaces/IiTryToken.sol |
| ./src/token/wiTRY/crosschain/interfaces/IUnstakeMessenger.sol |
| ./src/token/wiTRY/crosschain/interfaces/IwiTryVaultComposer.sol |
| ./src/token/wiTRY/crosschain/libraries/IVaultComposerSync.sol |
| ./src/token/wiTRY/crosschain/libraries/VaultComposerSync.sol |
| ./src/token/wiTRY/interfaces/IStakediTry.sol |
| ./src/token/wiTRY/interfaces/IStakediTryCooldown.sol |
| ./src/token/wiTRY/interfaces/IStakediTryCrosschain.sol |
| ./src/token/wiTRY/interfaces/IStakediTryFastRedeem.sol |
| ./src/token/wiTRY/interfaces/IiTrySiloDefinitions.sol |
| ./src/utils/IERC20Events.sol |
| ./src/utils/ISingleAdminAccessControl.sol |
| ./src/utils/SigUtils.sol |
| ./src/utils/SingleAdminAccessControl.sol |
| ./src/utils/SingleAdminAccessControlUpgradeable.sol |
| ./test/FastAccessVault.t.sol |
| ./test/FastAccessVaultInvariant.t.sol |
| ./test/Integration.HubChain.t.sol |
| ./test/StakediTry.redistributeLockedAmount.t.sol |
| ./test/StakediTryCrosschain.fastRedeem.t.sol |
| ./test/StakediTryFastRedeem.fuzz.t.sol |
| ./test/StakediTryV2.fastRedeem.t.sol |
| ./test/YieldForwarder.t.sol |
| ./test/crosschainTests/StakediTryCrosschain.t.sol |
| ./test/crosschainTests/crosschain/CrossChainTestBase.sol |
| ./test/crosschainTests/crosschain/CrossChainTestBase.t.sol |
| ./test/crosschainTests/crosschain/Step3_DeploymentTest.t.sol |
| ./test/crosschainTests/crosschain/Step4_MessageRelayTest.t.sol |
| ./test/crosschainTests/crosschain/Step5_BasicOFTTransfer.t.sol |
| ./test/crosschainTests/crosschain/Step6_VaultComposerTest.t.sol |
| ./test/crosschainTests/crosschain/Step7_OVaultDeposit.t.sol |
| ./test/crosschainTests/crosschain/Step8_ShareBridging.t.sol |
| ./test/crosschainTests/crosschain/UnstakeMessenger.t.sol |
| ./test/crosschainTests/crosschain/VaultComposerCrosschainUnstaking.t.sol |
| ./test/crosschainTests/crosschain/VaultComposerStructDecoding.t.sol |
| ./test/crosschainTests/wiTryVaultComposer.unit.t.sol |
| ./test/handlers/iTryIssuerHandler.sol |
| ./test/helpers/wiTryVaultComposerHarness.sol |
| ./test/iTryIssuer.admin.t.sol |
| ./test/iTryIssuer.base.t.sol |
| ./test/iTryIssuer.fuzz.t.sol |
| ./test/iTryIssuer.invariant.t.sol |
| ./test/iTryIssuer.mintFor.t.sol |
| ./test/iTryIssuer.redeemFor.t.sol |
| ./test/iTryIssuer.yield.t.sol |
| ./test/mocks/DLFToken.sol |
| ./test/mocks/MaliciousReceiver.sol |
| ./test/mocks/MockERC20.sol |
| ./test/mocks/MockERC20FailingTransfer.sol |
| ./test/mocks/MockIssuerContract.sol |
| ./test/mocks/MockLayerZeroEndpoint.sol |
| ./test/mocks/MockOFT.sol |
| ./test/mocks/MockStakediTryCrosschain.sol |
| ./test/mocks/SecurityMocks.sol |
| Totals: 94 |

