# Brix Money audit details
- Total Prize Pool: $23,000 in USDC
    - HM awards: up to $18,240 in USDC
        - If no valid Highs or Mediums are found, the HM pool is $0
    - QA awards: $760 in USDC
    - Judge awards: $3,500 in USDC
    - Scout awards: $500 in USDC
- [Read our guidelines for more details](https://docs.code4rena.com/competitions)
- Starts November 26, 2025 20:00 UTC
- Ends December 3, 2025 20:00 UTC)

### ❗ Important notes for wardens
1. A coded, runnable PoC is required for all High/Medium submissions to this audit. 
    - This repo includes a basic template to run the test suite.
    - PoCs must use the test suite provided in this repo.
    - Your submission will be marked as Insufficient if the POC is not runnable and working with the provided test suite.
    - Exception: PoC is optional (though recommended) for wardens with signal ≥ 0.68.
2. Judging phase risk adjustments (upgrades/downgrades):
    - High- or Medium-risk submissions downgraded by the judge to Low-risk (QA) will be ineligible for awards.
    - Upgrading a Low-risk finding from a QA report to a Medium- or High-risk finding is not supported.
    - As such, wardens are encouraged to select the appropriate risk level carefully during the submission phase.

## V12 findings

[V12](https://v12.zellic.io/) is [Zellic](https://zellic.io)'s in-house AI auditing tool. It is the only autonomous Solidity auditor that [reliably finds Highs and Criticals](https://www.zellic.io/blog/introducing-v12/). All issues found by V12 will be judged as out of scope and ineligible for awards.

V12 findings will be posted in this section within the first two days of the competition.  

## Publicly known issues

_Anything included in this section is considered a publicly known issue and is therefore ineligible for awards._

- Centralization risks are out of scope
- The function `processAccumulatedYield()` is currently gated to the `DEFAULT_ADMIN_ROLE`, when it should be gated to the `_YIELD_DISTRIBUTOR_ROLE`.

- Zellic report findings: 
    -  Blacklisted user can transfer tokens on behalf of non-blacklisted users using allowance - `_beforeTokenTransfer` does not validate `msg.sender`, a blacklisted caller can still initiate a same-chain token transfer on behalf of a non-blacklisted user as long as allowance exists.
    - Griefing attacks around the `MIN_SHARES` variable of the ERC2646 vault: The protocol will perform an initial deposit to offset this risk. 
    - The `redistributeLockedAmount` does not validate that the resulted `totalSupply` is not less than the minimum threshold. As a result of executing the `redistributeLockedAmount` function, the `totalSupply` amount may fall within a prohibited range between 0 and `MIN_SHARES` amount. And subsequent legitimate
deposits or withdrawals operations, which do not increase totalSupply to the `MIN_SHARES` value will be blocked.
    - iTRY backing can fall below 1:1 on NAV drop. If NAV drops below 1, iTRY becomes undercollateralized with no guaranteed, on-chain remediation. Holders bear insolvency risk until a top-up or discretionary admin intervention occurs.
    - Native fee loss on failed `wiTryVaultComposer.LzReceive` execution. In the case of underpayment, users will lose their fee and will have to pay twice to complete the unstake request.
    - Non-standard ERC20 tokens may break the transfer function. If a non-standard token is recovered using a raw transfer, the function may appear to succeed, even though no tokens were transferred, or it may revert unexpectedly. This can result in tokens becoming stuck in the contract, which breaks the tokens rescue mechanism.


✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

# Overview

[ ⭐️ SPONSORS: add info here ]

## Links

- **Previous audits:** Zellic - [see known issues](#publicly-known-issues)
  - ✅ SCOUTS: If there are multiple report links, please format them in a list.
- **Documentation:** https://hackmd.io/@EKJz7PaeT2GeAUJS83WWVw/SJPLb3QZWe
- **Website:** https://www.brix.money/
- **X/Twitter:** https://x.com/brix_money

---

# Scope

[ ✅ SCOUTS: add scoping and technical details here ]

### Files in scope
- ✅ This should be completed using the `metrics.md` file
- ✅ Last row of the table should be Total: SLOC
- ✅ SCOUTS: Have the sponsor review and and confirm in text the details in the section titled "Scoping Q amp; A"

*For sponsors that don't use the scoping tool: list all files in scope in the table below (along with hyperlinks) -- and feel free to add notes to emphasize areas of focus.*

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [contracts/folder/sample.sol](https://github.com/code-423n4/repo-name/blob/contracts/folder/sample.sol) | 123 | This contract does XYZ | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |

### Files out of scope
✅ SCOUTS: List files/directories out of scope

# Additional context

## Areas of concern (where to focus for bugs)
The issues we are most concerned are those related to unbacked minting of iTry, the theft or loss of funds when staking/unstaking (particularly crosschain), and blacklist/whitelist bugs that would impair rescue operations in case of hacks or similar black swan events. More generally, the areas we want to verify are:
- Are the extensions to the Ethena Staking contract secure?
- Is the Composer contract secure?
- Can the system result in minting unbacked iTry?
- Are the access controls effective?
- Can the system deal with black swan scenarios?

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## Main invariants

- The total issued iTry in the Issuer contract should always be be equal or lower to the total value of the DLF under custody. It should not be possible to mint "unbacked" iTry through the issuer. This does not mean that _totalIssuedITry needs to be equal to iTry.totalSupply(), though: there could be more than one minter contract using different backing assets.
- In the context of this audit, the NAV price queried can be assumed to be correct. The Oracle implementation will perform additional checks on the data feed and revert if it encounters issues.
- Blacklisted users cannot send/receive/mint/burn iTry tokens in any case.
- Only whitelisted user can send/receive/burn iTry tokens in a WHITELIST_ENABLED transfer state.
- Only non-blacklisted addresses can send/receive/burn iTry tokens in a FULLY_ENABLED transfer state.
- No adresses can send/receive tokens in a FULLY_DISABLED transfer state.

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## All trusted roles in the protocol

| Role                                | Description                       | Privileges | Controlled By |
| --------------------------------------- | ---------------------------- | --------| -------- | 
| Owner                          | Admin             | Root | Protocol Multisig
| User                             | User of the system                     | None | - |
| Blacklist Manager	| Manages blacklists in the system	| add/remove Blacklist entries for iTry and wiTry | Multisig |
| Whitelist Manager	| Manages whitelists in the system	| add/remove Blacklist entries for iTry	| Multisig |
| Soft Restricted Staker	| Can transfer the wiTry token, but cannot stake it	| Normal token usage, except staking to wiTry contract	| Blacklist Manager |
| Composer	| Accesses crosschain specific function in wiTry that allow to operate in name of another user |	Can use the composer-specific functions in the wiTry contract	| Owner |
| Minter |	Can mint iTry |	Can mint iTry	| Issuer contract| 
| Blacklisted	| Cannot transfer funds |	none |	Blacklist Manager |
| Whitelisted	| Can transfer funds in “onlyWhitelist” state	| Token transfer |	Whitelist Manager | 

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## Running tests

- foundryup
- make install
- copy .env.example and rename to .env
- edit custom RPC URLs for Sepolia and OP_Sepolia 
- make build-fast
- make test

✅ SCOUTS: Please format the response above 👆 using the template below👇

```bash
git clone https://github.com/code-423n4/2023-08-arbitrum
git submodule update --init --recursive
cd governance
foundryup
make install
make build
make sc-election-test
```
To run code coverage
```bash
make coverage
```

✅ SCOUTS: Add a screenshot of your terminal showing the test coverage

## Miscellaneous
Employees of Brix Money and employees' family members are ineligible to participate in this audit.

Code4rena's rules cannot be overridden by the contents of this README. In case of doubt, please check with C4 staff.




# Scope

*See [scope.txt](https://github.com/code-423n4/2025-11-brix-money/blob/main/scope.txt)*

### Files in scope


| File   | Logic Contracts | Interfaces | nSLOC | Purpose | Libraries used |
| ------ | --------------- | ---------- | ----- | -----   | ------------ |
| /src/protocol/FastAccessVault.sol | 1| **** | 118 | |@openzeppelin/contracts/access/Ownable.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol|
| /src/protocol/YieldForwarder.sol | 1| **** | 50 | |@openzeppelin/contracts/access/Ownable.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol|
| /src/protocol/iTryIssuer.sol | 1| **** | 278 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/iTRY/crosschain/iTryTokenOFT.sol | 1| **** | 87 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/iTRY/crosschain/iTryTokenOFTAdapter.sol | 1| **** | 5 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol|
| /src/token/iTRY/iTry.sol | 1| **** | 128 | |@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol<br>@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol<br>@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol<br>@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol|
| /src/token/wiTRY/StakediTry.sol | 1| **** | 140 | |@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol<br>@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol|
| /src/token/wiTRY/StakediTryCooldown.sol | 1| **** | 62 | ||
| /src/token/wiTRY/StakediTryCrosschain.sol | 1| **** | 65 | |@openzeppelin/contracts/token/ERC20/IERC20.sol|
| /src/token/wiTRY/StakediTryFastRedeem.sol | 1| **** | 67 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| /src/token/wiTRY/crosschain/UnstakeMessenger.sol | 1| **** | 110 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol<br>@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol<br>@openzeppelin/contracts/security/ReentrancyGuard.sol|
| /src/token/wiTRY/crosschain/wiTryOFT.sol | 1| **** | 45 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol|
| /src/token/wiTRY/crosschain/wiTryOFTAdapter.sol | 1| **** | 5 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol|
| /src/token/wiTRY/crosschain/wiTryVaultComposer.sol | 1| **** | 144 | |@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol<br>@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppReceiver.sol<br>@openzeppelin/contracts/token/ERC20/IERC20.sol|
| /src/token/wiTRY/iTrySilo.sol | 1| **** | 20 | |@openzeppelin/contracts/token/ERC20/IERC20.sol<br>@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol|
| **Totals** | **15** | **** | **1324** | | |

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
| ./src/protocol/interfaces/IFastAccessVault.sol |
| ./src/protocol/interfaces/IiTryIssuer.sol |
| ./src/protocol/periphery/CommonErrors.sol |
| ./src/protocol/periphery/IOracle.sol |
| ./src/protocol/periphery/IYieldProcessor.sol |
| /src/protocol/RedstoneNAVFeed.sol |
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
| Totals: 92 |

