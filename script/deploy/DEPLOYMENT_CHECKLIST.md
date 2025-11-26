# iTRY Protocol Deployment Checklist

**Version**: 1.0
**Last Updated**: 2025-11-06
**Target Networks**: Sepolia (Hub) + OP Sepolia (Spoke)

This checklist guides you through the complete deployment process for the iTRY Protocol across hub and spoke chains with crosschain unstaking support.

---

## 💡 Quick Tips

### Always Add --verify Flag to Deployments

```bash
forge script <script> --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

This verifies contracts on Etherscan immediately after deployment, saving time and preventing errors.

### Save Addresses to testnet.env Incrementally

**DO NOT wait until the end** - update testnet.env after each deployment step:

1. Run deployment script
2. Copy addresses from output
3. Open `testnet.env` and add/update the exported variables
4. Source the file: `source testnet.env`
5. Verify it loaded: `echo $HUB_ITRY_TOKEN`

This ensures subsequent scripts have access to the addresses they need.

### Verify Contracts on Etherscan Immediately

After each deployment, verify that contracts appear on Etherscan with a green checkmark:
- **Sepolia**: https://sepolia.etherscan.io/address/YOUR_ADDRESS
- **OP Sepolia**: https://sepolia-optimism.etherscan.io/address/YOUR_ADDRESS

If verification fails, re-run the verification command manually (see troubleshooting section).

---

## Prerequisites (Est. 15 minutes)

### Environment Setup
- [ ] **Clone repository and install dependencies**
  ```bash
  cd contracts
  forge install
  ```

- [ ] **Fund deployer address** (~0.5 ETH on each chain)
  - Sepolia: https://sepoliafaucet.com/
  - OP Sepolia: https://app.optimism.io/faucet
  - Verify balance: `cast balance $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC_URL`

- [ ] **Configure testnet.env file**
  - [ ] Set `DEPLOYER_PRIVATE_KEY` (testnet key only!)
  - [ ] Set `SEPOLIA_RPC_URL` (Alchemy/Infura)
  - [ ] Set `OP_SEPOLIA_RPC_URL` (Alchemy/Infura)
  - [ ] Set `ETHERSCAN_API_KEY` for verification
  - [ ] Verify configuration: `source testnet.env && echo $DEPLOYER_ADDRESS`

- [ ] **Pre-deployment validation**
  ```bash
  make build          # Compile all contracts
  make test           # Run full test suite (86/86 tests should pass)
  make fmt-check      # Verify code formatting
  ```

**Checkpoint**: All tests passing, environment configured, wallets funded

---

## Phase 1: Hub Chain Deployment (Sepolia) (Est. 2-3 minutes)

### Step 1.1: Deploy Core Infrastructure (~10-15 sec)
- [ ] **Run 01_DeployCore script**
  ```bash
  source testnet.env
  forge script script/deploy/hub/01_DeployCore.s.sol:DeployCore \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv
  ```

- [ ] **Verify core deployment**
  - [ ] Check console output for addresses:
    - `ORACLE`
    - `DLF_TOKEN`
    - `ITRY_TOKEN`
    - `CUSTODIAN`
  - [ ] Check deployment registry: `cat broadcast/deployment-addresses.json`

- [ ] **Step 1.1.1: Verify contracts on Etherscan**

  **Option 1: Add --verify flag to deployment (RECOMMENDED)**
  ```bash
  # Already included in command above with --verify flag
  # Check Etherscan after 1-2 minutes: https://sepolia.etherscan.io/address/[ADDRESS]
  ```

  **Option 2: Manual verification if --verify was forgotten or failed**
  ```bash
  # Get addresses from deployment output or broadcast/deployment-addresses.json

  forge verify-contract $HUB_ORACLE src/mocks/MockOracleSimplePrice.sol:MockOracleSimplePrice \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_DLF_TOKEN src/external/DLFToken.sol:DLFToken \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_ITRY_TOKEN src/iTRY/iTryToken.sol:iTryToken \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_CUSTODIAN src/mocks/MockCustodian.sol:MockCustodian \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch
  ```

  - [ ] **Confirm verification on Etherscan**: Visit https://sepolia.etherscan.io/address/[ITRY_TOKEN] and check for green checkmark

- [ ] **Step 1.1.2: Save addresses to testnet.env IMMEDIATELY**
  ```bash
  # Open testnet.env and add/update these lines:
  export HUB_ORACLE="0x..."           # From deployment output
  export HUB_DLF_TOKEN="0x..."        # From deployment output
  export HUB_ITRY_TOKEN="0x..."       # From deployment output
  export HUB_CUSTODIAN="0x..."        # From deployment output

  # IMPORTANT: Source the file so variables are available for next steps
  source testnet.env

  # Verify variables loaded correctly
  echo "HUB_ITRY_TOKEN: $HUB_ITRY_TOKEN"
  ```

**Deployed**: Oracle, Mock DLF Token, iTRY Token, MockCustodian

---

### Step 1.2: Deploy Protocol Contracts (~20-30 sec)
- [ ] **Run 02_DeployProtocol script**
  ```bash
  forge script script/deploy/hub/02_DeployProtocol.s.sol:DeployProtocol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv
  ```

- [ ] **Verify protocol deployment**
  - [ ] Check console output for addresses:
    - `BUFFER_POOL`
    - `STAKING` (StakedUSDeV2)
    - `YIELD_DISTRIBUTOR`
    - `CONTROLLER`
    - `USDE_CROSSCHAIN_SILO` (auto-deployed with StakedUSDeV2)
  - [ ] Verify contract sizes are within 24KB limit
  - [ ] Confirm USDeCrosschainSilo is deployed and linked to StakedUSDeV2

- [ ] **Step 1.2.1: Verify contracts on Etherscan**

  **Option 1: Automatic verification with --verify flag (already done above)**

  **Option 2: Manual verification if needed**
  ```bash
  # Verify protocol contracts
  forge verify-contract $HUB_BUFFER_POOL src/iTRY/BufferPool.sol:BufferPool \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_STAKING src/wiTRY/ComposerStakedUSDeV2.sol:ComposerStakedUSDeV2 \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_YIELD_DISTRIBUTOR src/iTRY/YieldDistributor.sol:YieldDistributor \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_CONTROLLER src/iTRY/iTryController.sol:iTryController \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  # Get USDeCrosschainSilo address from StakedUSDeV2
  USDE_SILO=$(cast call $HUB_STAKING "silo()(address)" --rpc-url $SEPOLIA_RPC_URL)

  forge verify-contract $USDE_SILO src/wiTRY/crosschain/USDeCrosschainSilo.sol:USDeCrosschainSilo \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch
  ```

  - [ ] **Confirm verification on Etherscan**: Check each contract address on https://sepolia.etherscan.io/

- [ ] **Step 1.2.2: Update testnet.env with protocol addresses IMMEDIATELY**
  ```bash
  # Open testnet.env and add/update these lines:
  export HUB_BUFFER_POOL="0x..."              # From deployment output
  export HUB_STAKING="0x..."                  # From deployment output
  export HUB_YIELD_DISTRIBUTOR="0x..."        # From deployment output
  export HUB_CONTROLLER="0x..."               # From deployment output
  export USDE_CROSSCHAIN_SILO="0x..."         # From deployment output or cast call

  # Source the updated file
  source testnet.env

  # Verify variables loaded
  echo "HUB_STAKING: $HUB_STAKING"
  echo "HUB_CONTROLLER: $HUB_CONTROLLER"
  ```

**Deployed**: BufferPool, StakedUSDeV2, YieldDistributor, Controller, USDeCrosschainSilo
**Note**: USDeCrosschainSilo is automatically deployed by 02_DeployProtocol (no separate step needed)

---

### Step 1.3: Deploy CrossChain Infrastructure (~40-60 sec)
- [ ] **Run 03_DeployCrossChain script**
  ```bash
  forge script script/deploy/hub/03_DeployCrossChain.s.sol:DeployCrossChain \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv
  ```

- [ ] **Verify crosschain deployment**
  - [ ] Check console output for addresses:
    - `ITRY_ADAPTER` (iTryTokenAdapter)
    - `SHARE_ADAPTER` (ShareOFTAdapter)
    - `VAULT_COMPOSER` (VaultComposer with OApp support)
  - [ ] Verify LayerZero endpoint: `0x6EDCE65403992e310A62460808c4b910D972f10f`
  - [ ] Confirm VaultComposer has OApp messaging capabilities

- [ ] **Step 1.3.1: Verify contracts on Etherscan**

  **Option 1: Automatic verification with --verify flag (already done above)**

  **Option 2: Manual verification if needed**
  ```bash
  # Verify crosschain contracts
  forge verify-contract $HUB_ITRY_ADAPTER src/iTRY/crosschain/iTryTokenAdapter.sol:iTryTokenAdapter \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $HUB_SHARE_ADAPTER src/wiTRY/crosschain/ShareOFTAdapter.sol:ShareOFTAdapter \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $VAULT_COMPOSER src/wiTRY/VaultComposer.sol:VaultComposer \
    --chain-id 11155111 \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --watch
  ```

  - [ ] **Confirm verification on Etherscan**: Check each contract on https://sepolia.etherscan.io/

- [ ] **Step 1.3.2: Save addresses to testnet.env IMMEDIATELY**
  ```bash
  # Open testnet.env and add/update these lines:
  export HUB_ITRY_ADAPTER="0x..."     # From deployment output
  export HUB_SHARE_ADAPTER="0x..."    # From deployment output
  export VAULT_COMPOSER="0x..."       # From deployment output (CRITICAL for Phase 2)

  # Source the updated file
  source testnet.env

  # Verify variables loaded - ESPECIALLY VAULT_COMPOSER (needed for spoke deployment)
  echo "HUB_ITRY_ADAPTER: $HUB_ITRY_ADAPTER"
  echo "HUB_SHARE_ADAPTER: $HUB_SHARE_ADAPTER"
  echo "VAULT_COMPOSER: $VAULT_COMPOSER"
  ```

**Deployed**: iTryTokenAdapter, ShareOFTAdapter, VaultComposer (OApp)

---

### Step 1.4: Setup State and Permissions (~10-15 sec)
- [ ] **Run 04_SetupState script**
  ```bash
  forge script script/deploy/hub/04_SetupTestnetState.s.sol:SetupTestnetState \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Verify state configuration**
  - [ ] Check role assignments (minters, redeemers, etc.)
  - [ ] Verify controller has proper permissions on iTRY token
  - [ ] Verify VaultComposer has COMPOSER_ROLE on StakedUSDeV2
  - [ ] Verify USDeCrosschainSilo has proper vault access
  - [ ] Check initial oracle NAV price is set (20e18)

**Configured**: Roles, permissions, initial state

---

### Step 1.5: Verify Hub Deployment (Optional but Recommended)
- [ ] **Run verification script**
  ```bash
  forge script script/verify/VerifyDeployment.s.sol:VerifyDeployment \
    --rpc-url $SEPOLIA_RPC_URL \
    -vvv
  ```

- [ ] **Manual verification checks**
  ```bash
  # Check iTRY total supply
  cast call $HUB_ITRY_TOKEN "totalSupply()(uint256)" --rpc-url $SEPOLIA_RPC_URL

  # Check StakedUSDeV2 silo address
  cast call $HUB_STAKING "silo()(address)" --rpc-url $SEPOLIA_RPC_URL

  # Check VaultComposer endpoint
  cast call $VAULT_COMPOSER "endpoint()(address)" --rpc-url $SEPOLIA_RPC_URL
  ```

**Checkpoint**: Hub chain fully deployed and verified

---

### Step 1.6: Verify testnet.env Has All Hub Addresses
- [ ] **Verify all Phase 1 addresses are documented in testnet.env**

  **IMPORTANT**: You should have been updating testnet.env incrementally after Steps 1.1, 1.2, and 1.3.
  This step is just a final verification checkpoint.

  ```bash
  # Open testnet.env and verify all Phase 1 addresses are set:
  export HUB_ORACLE="0x..."
  export HUB_DLF_TOKEN="0x..."
  export HUB_ITRY_TOKEN="0x..."
  export HUB_CUSTODIAN="0x..."
  export HUB_CONTROLLER="0x..."
  export HUB_BUFFER_POOL="0x..."
  export HUB_STAKING="0x..."
  export HUB_YIELD_DISTRIBUTOR="0x..."
  export USDE_CROSSCHAIN_SILO="0x..."
  export HUB_ITRY_ADAPTER="0x..."
  export HUB_SHARE_ADAPTER="0x..."
  export VAULT_COMPOSER="0x..."
  export HUB_CHAIN_EID=40161
  ```

- [ ] **Source the file and verify variables are loaded**
  ```bash
  # Source updated environment
  source testnet.env

  # Verify critical variables for Phase 2
  echo "VAULT_COMPOSER: $VAULT_COMPOSER"
  echo "HUB_ITRY_ADAPTER: $HUB_ITRY_ADAPTER"
  echo "HUB_SHARE_ADAPTER: $HUB_SHARE_ADAPTER"
  echo "HUB_STAKING: $HUB_STAKING"
  ```

- [ ] **Optional: Commit to git** (if tracking testnet deployments)
  ```bash
  git add testnet.env
  git commit -m "chore: update testnet.env with Phase 1 hub chain addresses"
  ```

**Checkpoint**: All Phase 1 hub addresses documented and loaded in testnet.env

---

### Phase 1 Summary: Hub Chain Etherscan Verification

After completing Phase 1, verify all hub contracts on Etherscan:

- [ ] **Batch verification (recommended)**
  ```bash
  # Use makefile if available
  make verify-sepolia
  ```

- [ ] **Manual verification for each contract**
  ```bash
  source testnet.env

  # Core contracts
  forge verify-contract $HUB_ORACLE src/mocks/MockOracleSimplePrice.sol:MockOracleSimplePrice \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_DLF_TOKEN src/external/DLFToken.sol:DLFToken \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_ITRY_TOKEN src/iTRY/iTryToken.sol:iTryToken \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_CUSTODIAN src/mocks/MockCustodian.sol:MockCustodian \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  # Protocol contracts
  forge verify-contract $HUB_BUFFER_POOL src/iTRY/BufferPool.sol:BufferPool \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_STAKING src/wiTRY/ComposerStakedUSDeV2.sol:ComposerStakedUSDeV2 \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_YIELD_DISTRIBUTOR src/iTRY/YieldDistributor.sol:YieldDistributor \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_CONTROLLER src/iTRY/iTryController.sol:iTryController \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $USDE_CROSSCHAIN_SILO src/wiTRY/crosschain/USDeCrosschainSilo.sol:USDeCrosschainSilo \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  # Crosschain contracts
  forge verify-contract $HUB_ITRY_ADAPTER src/iTRY/crosschain/iTryTokenAdapter.sol:iTryTokenAdapter \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $HUB_SHARE_ADAPTER src/wiTRY/crosschain/ShareOFTAdapter.sol:ShareOFTAdapter \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch

  forge verify-contract $VAULT_COMPOSER src/wiTRY/VaultComposer.sol:VaultComposer \
    --chain-id 11155111 --etherscan-api-key $ETHERSCAN_API_KEY --watch
  ```

- [ ] **Verify all contracts on Sepolia Etherscan**
  - Visit: https://sepolia.etherscan.io/
  - Search for each contract address
  - Confirm green checkmark (verified)

**Checkpoint**: All Phase 1 hub contracts verified on Etherscan

---

## Phase 2: Spoke Chain Deployment (OP Sepolia) (Est. 30-45 sec)

### Step 2.1: Update testnet.env with Hub Addresses
- [ ] **Copy hub deployment addresses to testnet.env**
  ```bash
  export HUB_ITRY_ADAPTER="0x..."      # From 03_DeployCrossChain output
  export HUB_SHARE_ADAPTER="0x..."     # From 03_DeployCrossChain output
  export VAULT_COMPOSER="0x..."        # From 03_DeployCrossChain output
  export HUB_CHAIN_EID=40161           # Sepolia LayerZero EID
  ```

- [ ] **Verify environment is sourced**
  ```bash
  source testnet.env
  echo "Hub iTRY Adapter: $HUB_ITRY_ADAPTER"
  echo "Hub Share Adapter: $HUB_SHARE_ADAPTER"
  echo "Vault Composer: $VAULT_COMPOSER"
  ```

---

### Step 2.2: Deploy Spoke Chain Contracts (~30-45 sec)
- [ ] **Run SpokeChainDeployment script**
  ```bash
  forge script script/deploy/spoke/SpokeChainDeployment.s.sol:DeploySpoke \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvv
  ```

- [ ] **Verify spoke deployment**
  - [ ] Check console output for addresses:
    - `ITRY_TOKEN_OFT`
    - `SHARE_OFT`
    - `UNSTAKE_MESSENGER`
  - [ ] Verify spoke→hub peers were auto-configured:
    - iTryTokenOFT → iTryTokenAdapter
    - ShareOFT → ShareOFTAdapter
    - UnstakeMessenger → VaultComposer
  - [ ] Note the spoke chain EID: `40232` (OP Sepolia)
  - [ ] Copy addresses for next phase

- [ ] **Step 2.2.1: Verify contracts on OP Sepolia Etherscan**

  **Option 1: Automatic verification with --verify flag (already done above)**

  **Option 2: Manual verification if needed (OP Sepolia requires different verifier URL)**
  ```bash
  # Verify spoke chain contracts on OP Sepolia
  # NOTE: OP Sepolia requires --verifier-url and different API key

  forge verify-contract $SPOKE_ITRY_OFT src/iTRY/crosschain/iTryTokenOFT.sol:iTryTokenOFT \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $SPOKE_SHARE_OFT src/wiTRY/crosschain/ShareOFT.sol:ShareOFT \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $UNSTAKE_MESSENGER src/wiTRY/crosschain/UnstakeMessenger.sol:UnstakeMessenger \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch
  ```

  - [ ] **Confirm verification on OP Sepolia Etherscan**: Visit https://sepolia-optimism.etherscan.io/address/[ADDRESS]

- [ ] **Step 2.2.2: Save spoke addresses to testnet.env IMMEDIATELY**
  ```bash
  # Open testnet.env and add/update these lines:
  export SPOKE_ITRY_OFT="0x..."           # From deployment output
  export SPOKE_SHARE_OFT="0x..."          # From deployment output
  export UNSTAKE_MESSENGER="0x..."        # From deployment output
  export SPOKE_CHAIN_EID=40232

  # Source the updated file
  source testnet.env

  # Verify variables loaded - these are CRITICAL for Phase 3 configuration
  echo "SPOKE_ITRY_OFT: $SPOKE_ITRY_OFT"
  echo "SPOKE_SHARE_OFT: $SPOKE_SHARE_OFT"
  echo "UNSTAKE_MESSENGER: $UNSTAKE_MESSENGER"
  ```

**Deployed**: iTryTokenOFT, ShareOFT, UnstakeMessenger
**Auto-configured**: Spoke→Hub peer relationships (unidirectional)

---

### Step 2.3: Verify testnet.env has Complete Configuration
- [ ] **Verify all Phase 2 addresses are documented in testnet.env**
  ```bash
  # Open testnet.env and verify spoke addresses are set:
  export SPOKE_ITRY_OFT="0x..."
  export SPOKE_SHARE_OFT="0x..."
  export UNSTAKE_MESSENGER="0x..."
  export SPOKE_CHAIN_EID=40232

  # Also verify hub addresses from Phase 1:
  export HUB_ITRY_ADAPTER="0x..."
  export HUB_SHARE_ADAPTER="0x..."
  export VAULT_COMPOSER="0x..."
  export HUB_CHAIN_EID=40161
  ```

- [ ] **Source updated environment**
  ```bash
  source testnet.env
  ```

- [ ] **Verify environment variables are loaded**
  ```bash
  echo "Spoke iTRY OFT: $SPOKE_ITRY_OFT"
  echo "Spoke Share OFT: $SPOKE_SHARE_OFT"
  echo "Unstake Messenger: $UNSTAKE_MESSENGER"
  echo "Vault Composer: $VAULT_COMPOSER"
  ```

**Checkpoint**: Spoke chain deployed, spoke→hub peers configured, addresses saved

**Environment Variables for 01_ConfigurePeers.s.sol**:
- SPOKE_ITRY_OFT - iTryTokenOFT address on spoke
- SPOKE_SHARE_OFT - ShareOFT address on spoke
- UNSTAKE_MESSENGER - UnstakeMessenger address on spoke
- VAULT_COMPOSER - VaultComposer address on hub (from Step 1.3)
- SPOKE_CHAIN_EID - LayerZero EID for spoke chain (40232)

---

### Phase 2 Summary: Spoke Chain Etherscan Verification

After completing Phase 2, verify all spoke contracts on OP Sepolia Etherscan:

- [ ] **Batch verification (recommended)**
  ```bash
  # Use makefile if available
  make verify-op-sepolia
  ```

- [ ] **Manual verification for each spoke contract**
  ```bash
  source testnet.env

  # Spoke chain contracts (OP Sepolia)
  forge verify-contract $SPOKE_ITRY_OFT src/iTRY/crosschain/iTryTokenOFT.sol:iTryTokenOFT \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $SPOKE_SHARE_OFT src/wiTRY/crosschain/ShareOFT.sol:ShareOFT \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch

  forge verify-contract $UNSTAKE_MESSENGER src/wiTRY/crosschain/UnstakeMessenger.sol:UnstakeMessenger \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch
  ```

- [ ] **Verify all contracts on OP Sepolia Etherscan**
  - Visit: https://sepolia-optimism.etherscan.io/
  - Search for each contract address
  - Confirm green checkmark (verified)

**Checkpoint**: All Phase 2 spoke contracts verified on Etherscan

---

## Phase 3: Hub→Spoke Configuration (Est. 1-2 minutes)

**Important**: Configuration scripts are numbered to enforce execution order:
1. **01_ConfigurePeers** - Set up peer relationships (hub→spoke)
2. **02_SetLibraries** - Configure LayerZero libraries (MUST RUN ON BOTH CHAINS)
3. **03-05_SetEnforcedOptions** - Set message gas/value parameters (can run in any order)

### Step 3.1: Configure Hub→Spoke Peer Relationships (~15-20 sec)
- [ ] **Run 01_ConfigurePeers script on Sepolia**
  ```bash
forge script script/config/01_ConfigurePeers.s.sol:ConfigurePeers01 \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```
  This configures 3 hub→spoke peer relationships:
  - iTryTokenAdapter → iTryTokenOFT
  - ShareOFTAdapter → ShareOFT
  - VaultComposer → UnstakeMessenger

- [ ] **Verify bidirectional peers are configured**
  ```bash
  # Verify iTryTokenAdapter recognizes iTryTokenOFT
  cast call $HUB_ITRY_ADAPTER "peers(uint32)(bytes32)" $SPOKE_CHAIN_EID \
    --rpc-url $SEPOLIA_RPC_URL

  # Verify ShareOFTAdapter recognizes ShareOFT
  cast call $HUB_SHARE_ADAPTER "peers(uint32)(bytes32)" $SPOKE_CHAIN_EID \
    --rpc-url $SEPOLIA_RPC_URL

  # Verify VaultComposer recognizes UnstakeMessenger
  cast call $VAULT_COMPOSER "peers(uint32)(bytes32)" $SPOKE_CHAIN_EID \
    --rpc-url $SEPOLIA_RPC_URL
  ```

**Configured**: Hub→Spoke peer relationships (iTRY, wiTRY, UnstakeMessenger)
**Note**: Required environment variables are loaded from testnet.env:
- SPOKE_ITRY_OFT, SPOKE_SHARE_OFT, SPOKE_UNSTAKE_MESSENGER (or UNSTAKE_MESSENGER)
- VAULT_COMPOSER, SPOKE_CHAIN_EID
- Hub addresses (iTryTokenAdapter, ShareOFTAdapter) are loaded from DeploymentRegistry

---

### Step 3.2: Set LayerZero Libraries on HUB (Sepolia) (~10-15 sec)
- [ ] **Run 02_SetLibraries script on Sepolia**
  ```bash
  forge script script/config/02_SetLibraries.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```
  Estimated time: ~10-15 seconds

**Configured**: LayerZero Send/Receive libraries for hub chain messaging

---

### Step 3.3: Set LayerZero Libraries on SPOKE (OP Sepolia) (~10-15 sec)
- [ ] **Run 02_SetLibraries script on OP Sepolia**
  ```bash
  forge script script/config/02_SetLibraries.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```
  Estimated time: ~10-15 seconds

  ⚠️ **CRITICAL**: This script must run on BOTH chains to configure messaging infrastructure

**Configured**: LayerZero Send/Receive libraries for spoke chain messaging

---

### Step 3.4: Set Enforced Options on ShareAdapter (Hub) (~10-15 sec)
- [ ] **Run 03_SetEnforcedOptionsShareAdapter on Sepolia**
  ```bash
forge script script/config/03_SetEnforcedOptionsShareAdapter.s.sol:SetEnforcedOptionsShareAdapter03 \      
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Verify enforced options**
  ```bash
  cast call $HUB_SHARE_ADAPTER "enforcedOptions(uint32,uint16)(bytes)" 40232 1 \
    --rpc-url $SEPOLIA_RPC_URL
  ```
  - [ ] Confirm lzReceive gas: 200,000
  - [ ] Confirm msgType: 1 (SEND - no compose for refunds)

**Configured**: ShareAdapter enforced options for refund flow

---

### Step 3.5: Set Enforced Options on ShareOFT (Spoke) (~10-15 sec)
- [ ] **Run 04_SetEnforcedOptionsShareOFT on OP Sepolia**
  ```bash
  forge script script/config/04_SetEnforcedOptionsShareOFT.s.sol:SetEnforcedOptionsShareOFT04 \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Verify enforced options**
  ```bash
  cast call $SPOKE_SHARE_OFT "enforcedOptions(uint32,uint16)(bytes)" 40161 2 \
    --rpc-url $OP_SEPOLIA_RPC_URL
  ```
  - [ ] Confirm lzReceive gas: 200,000
  - [ ] Confirm lzCompose gas: 500,000
  - [ ] Confirm lzCompose value: 0.01 ETH

**Configured**: ShareOFT enforced options for async redeem with compose

---

### Step 3.6: Set Enforced Options on iTryAdapter (Hub) (~10-15 sec)
- [ ] **Run 06_SetEnforcedOptionsiTryAdapter on Sepolia**
  ```bash
  forge script script/config/06_SetEnforcedOptionsiTryAdapter.s.sol:SetEnforcedOptionsiTryAdapter06 \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Verify enforced options**
  ```bash
  cast call $HUB_ITRY_ADAPTER "enforcedOptions(uint32,uint16)(bytes)" 40232 1 \
    --rpc-url $SEPOLIA_RPC_URL
  ```
  - [ ] Confirm lzReceive gas: 200,000
  - [ ] Confirm msgType: 1 (SEND - for return leg of unstaking)

**Configured**: iTryAdapter enforced options for crosschain unstaking return leg

**⚠️ CRITICAL**: This step is required for crosschain unstaking. Without it, the VaultComposer will fail with `Executor_NoOptions()` error when quoting the return leg.

---

### Step 3.8: Verify Peer Configuration
- [ ] **Run VerifyPeers script**
  ```bash
  # Verify on Sepolia (Hub)
  forge script script/verify/VerifyPeers.s.sol:VerifyPeers \
    --rpc-url $SEPOLIA_RPC_URL \
    -vvv

  # Verify on OP Sepolia (Spoke)
  forge script script/verify/VerifyPeers.s.sol:VerifyPeers \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    -vvv
  ```

- [ ] **Check LayerZero scan for peer relationships**
  - Visit: https://testnet.layerzeroscan.com/
  - Search for contract addresses
  - Verify peer configurations match

**Checkpoint**: All peer relationships configured, libraries set, and enforced options configured

---

## Phase 4: Final Verification and Testing (Est. 5-10 minutes)

### Step 4.1: Update testnet.env with Final Configuration
- [ ] **Document all deployed addresses in testnet.env**
  - [ ] Hub chain addresses (Sepolia)
    - [ ] `HUB_ITRY_TOKEN`
    - [ ] `HUB_DLF_TOKEN`
    - [ ] `HUB_ORACLE`
    - [ ] `HUB_CUSTODIAN`
    - [ ] `HUB_CONTROLLER`
    - [ ] `HUB_BUFFER_POOL`
    - [ ] `HUB_STAKING`
    - [ ] `HUB_YIELD_DISTRIBUTOR`
    - [ ] `HUB_ITRY_ADAPTER`
    - [ ] `HUB_SHARE_ADAPTER`
    - [ ] `VAULT_COMPOSER`
    - [ ] `USDE_CROSSCHAIN_SILO`

  - [ ] Spoke chain addresses (OP Sepolia)
    - [ ] `SPOKE_ITRY_OFT`
    - [ ] `SPOKE_SHARE_OFT`
    - [ ] `SPOKE_UNSTAKE_MESSENGER`

  - [ ] LayerZero configuration
    - [ ] `HUB_CHAIN_EID=40161`
    - [ ] `SPOKE_CHAIN_EID=40232`

- [ ] **Commit testnet.env updates** (if not gitignored)
  ```bash
  git add testnet.env
  git commit -m "docs: update testnet.env with deployment addresses"
  ```

---

### Step 4.2: Run Comprehensive Verification Suite
- [ ] **Verify hub chain deployment**
  ```bash
  forge script script/verify/VerifyDeployment.s.sol:VerifyDeployment \
    --rpc-url $SEPOLIA_RPC_URL \
    -vvv
  ```

- [ ] **Verify spoke chain deployment**
  ```bash
  forge script script/verify/ShowTestnetAddresses.s.sol:ShowTestnetAddresses \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    -vvv
  ```

- [ ] **Check all contract verifications on block explorers**
  - Sepolia: https://sepolia.etherscan.io/
  - OP Sepolia: https://sepolia-optimism.etherscan.io/

- [ ] **Alternative: Use Makefile verification targets**
  ```bash
  # Batch verify all Sepolia contracts (if makefile targets exist)
  make verify-sepolia

  # Batch verify all OP Sepolia contracts (if makefile targets exist)
  make verify-op-sepolia
  ```

---

### Step 4.3: Optional - Run Functional Tests

**Bridge Tests** (~2-3 minutes per test)
- [x] **Test iTRY bridging hub→spoke**
  ```bash
  forge script script/test/bridge/BridgeITRY_HubToSpoke_RedeemerAddress.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [x] **Test iTRY bridging spoke→hub**
  ```bash
  forge script script/test/bridge/BridgeITRY_SpokeToHub_RedeemerAddress.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [x] **Test wiTRY bridging hub→spoke**
  ```bash
  forge script script/test/bridge/BridgeWITRY_HubToSpoke_Staker1.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [x] **Test wiTRY bridging spoke→hub**
  ```bash
  forge script script/test/bridge/BridgeWITRY_SpokeToHub_Staker1.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

**Composer Tests** (~3-5 minutes per test)
- [x] **Test VaultComposer stake and bridge**
  ```bash
  forge script script/test/composer/StakeAndBridgeWITRY_HubToSpoke_RedeemerAddress.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [x] **Test BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress**
  ```bash
  forge script script/test/composer/BridgeStakeAndBridgeBack_SpokeToHubToSpoke_RedeemerAddress.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Test bridge and initiate cooldown**
  ```bash
  forge script script/test/composer/BridgeAndInitiateCooldown_SpokeToHub_RedeemerAddress.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

- [ ] **Test initiate cooldown refund**
  ```bash
  forge script script/test/composer/InitiateCooldownRefund_SpokeToHub_RedeemerAddress.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

**Crosschain Unstake Tests** (~5-7 minutes per test)
- [ ] **Test crosschain unstake flow**
  ```bash
  forge script script/test/composer/CrosschainUnstake_SpokeToHubToSpoke_RedeemerAddress.s.sol \
    --rpc-url $OP_SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

**E2E Validation** (~5-10 minutes)
- [ ] **Run full E2E validation suite**
  ```bash
  forge script script/test/e2e/TestnetE2EValidation.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    -vvv
  ```

---

## Troubleshooting

### Common Issues and Solutions

#### Deployment Failures

**Issue**: `ERROR: Factory already exists`
**Solution**: Network state is dirty. Either:
- Reset Anvil: `pkill anvil && anvil` (local only)
- Use existing addresses from registry: `cat broadcast/deployment-addresses.json`
- Deploy to fresh testnet or use different salt

**Issue**: `Contract size exceeds 24KB`
**Solution**:
- Check `make check-size` output
- Review optimizer settings in `foundry.toml`
- Contact team if size is critical

**Issue**: `Insufficient funds for gas`
**Solution**:
- Check balance: `cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL`
- Fund from faucets (see Prerequisites)
- Ensure you have ~0.5 ETH on each chain

---

#### Peer Configuration Issues

**Issue**: `Broadcaster is NOT owner of adapter`
**Solution**: Ensure `DEPLOYER_PRIVATE_KEY` matches the account that deployed the contracts

**Issue**: `Peer not recognized / InvalidPeer error`
**Solution**:
- Verify peer addresses are correct in testnet.env
- Run VerifyPeers script to check configuration
- Check LayerZero scan: https://testnet.layerzeroscan.com/

**Issue**: `Enforced options not set`
**Solution**: Re-run the SetEnforcedOptions scripts (idempotent)

---

#### Crosschain Message Failures

**Issue**: `LayerZero message not delivered`
**Solution**:
- Check LayerZero scan: https://testnet.layerzeroscan.com/
- Verify enforced options are set (Step 3.2-3.4)
- Ensure sufficient gas limits (350k for UnstakeMessenger)
- Wait 5-10 minutes for testnet relayer processing

**Issue**: `InsufficientGasForCompose error`
**Solution**:
- Increase lzCompose gas in SetEnforcedOptionsShareOFT
- Verify caller provides enough native gas (0.01 ETH)

**Issue**: `Crosschain unstake fails at _lzReceive`
**Solution**:
- Check UnstakeMessenger enforced options (350k gas)
- Verify VaultComposer has COMPOSER_ROLE on vault
- Verify USDeCrosschainSilo is properly linked to StakedUSDeV2

---

#### Verification Issues

**Issue**: `Etherscan verification failed - "Unable to locate ContractCode"`
**Solution**:
- Wait 1-2 minutes after deployment for blockchain propagation
- Verify contract exists: `cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL`
- Retry verification after waiting

**Issue**: `Etherscan verification failed - "Invalid API Key"`
**Solution**:
- Check `ETHERSCAN_API_KEY` is set: `echo $ETHERSCAN_API_KEY`
- For OP Sepolia, ensure `OP_ETHERSCAN_API_KEY` is set
- Get API key from: https://etherscan.io/myapikey (Sepolia) or https://optimistic.etherscan.io/myapikey (OP Sepolia)
- Source testnet.env: `source testnet.env`

**Issue**: `Verification failed - "Constructor arguments mismatch"`
**Solution**:
- Check deployment script for constructor args
- Encode args correctly: `cast abi-encode "constructor(address,address)" $ARG1 $ARG2`
- Pass encoded args: `--constructor-args <encoded_args>`
- Example:
  ```bash
  ARGS=$(cast abi-encode "constructor(address,address,address)" $TOKEN $ENDPOINT $DELEGATE)
  forge verify-contract $CONTRACT_ADDRESS <ContractName> \
    --chain-id 11155111 \
    --constructor-args $ARGS \
    --etherscan-api-key $ETHERSCAN_API_KEY
  ```

**Issue**: `Verification failed - "Contract source code already verified"`
**Solution**:
- This is success! Check Etherscan to confirm
- Visit: https://sepolia.etherscan.io/address/$CONTRACT_ADDRESS#code

**Issue**: `Rate limit exceeded`
**Solution**:
- Etherscan free tier: 5 requests/second, 100,000 requests/day
- Wait 10-15 seconds between verification attempts
- Use `--watch` flag instead of manual polling
- Consider upgrading Etherscan API plan for batch verification

**Issue**: `Verification failed on OP Sepolia - wrong API endpoint`
**Solution**:
- Always specify `--verifier-url https://api-sepolia-optimistic.etherscan.io/api`
- Use `--etherscan-api-key $OP_ETHERSCAN_API_KEY` (NOT $ETHERSCAN_API_KEY)
- Example:
  ```bash
  forge verify-contract $CONTRACT_ADDRESS <ContractName> \
    --chain-id 11155420 \
    --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
    --etherscan-api-key $OP_ETHERSCAN_API_KEY \
    --watch
  ```

**Issue**: `DeploymentRegistry not found`
**Solution**: Registry is created automatically. If missing:
- Check `broadcast/deployment-addresses.json` exists
- Re-run deployment scripts to regenerate

**Issue**: `Verification works but contract shows "Unverified" on Etherscan`
**Solution**:
- Wait 5-10 minutes for Etherscan indexing
- Hard refresh browser (Ctrl+F5)
- Check for verification status: visit contract page → "Contract" tab → should show green checkmark
- Re-verify if needed (idempotent operation)

---

### Getting Help

- **Documentation**: `/docs/architecture/DEPLOYMENT_GUIDE.md`
- **Specifications**: `/developmentContext/smartContractDevelopmentContext/`
- **LayerZero Docs**: https://docs.layerzero.network/v2
- **Block Explorers**:
  - Sepolia: https://sepolia.etherscan.io/
  - OP Sepolia: https://sepolia-optimism.etherscan.io/
- **LayerZero Scan**: https://testnet.layerzeroscan.com/

---

## Deployment Summary

**Total Estimated Time**: 15-25 minutes (excluding optional functional tests)

### Hub Chain (Sepolia) - 5 Scripts
1. ✅ 01_DeployCore (~10-15 sec)
2. ✅ 02_DeployProtocol (~20-30 sec) - *Auto-deploys USDeCrosschainSilo*
3. ✅ 03_DeployCrossChain (~40-60 sec)
4. ✅ 04_SetupState (~10-15 sec)

### Spoke Chain (OP Sepolia) - 1 Script
5. ✅ SpokeChainDeployment (~30-45 sec) - *Auto-sets spoke→hub peers*

### Configuration Scripts (Run After Deployment)

**Configuration order MUST be followed:**

#### Phase 3.1: Peer Configuration (Sepolia Hub)
6. ✅ 01_ConfigurePeers (~15-20 sec)
   - Sets 3 hub→spoke peer relationships:
   - iTryTokenAdapter → iTryTokenOFT
   - ShareOFTAdapter → ShareOFT
   - VaultComposer → UnstakeMessenger

#### Phase 3.2-3.3: Library Configuration (BOTH Chains - CRITICAL)
7. ✅ 02_SetLibraries on Sepolia (~10-15 sec)
8. ✅ 02_SetLibraries on OP Sepolia (~10-15 sec)
   - ⚠️ **MUST run on BOTH chains**
   - Configures LayerZero Send/Receive libraries
   - Required for message routing

#### Phase 3.4-3.6: Enforced Options (Can run in any order after libraries are set)
9. ✅ 03_SetEnforcedOptionsShareAdapter on Sepolia (~10-15 sec)
10. ✅ 04_SetEnforcedOptionsShareOFT on OP Sepolia (~10-15 sec)
11. ✅ 06_SetEnforcedOptionsiTryAdapter on Sepolia (~10-15 sec)

**Note:** UnstakeMessenger uses dynamic quoting with 10% buffer instead of enforced options to avoid overpaying and handle realtime gas prices.

**Execution Order Summary:**
1. **01_ConfigurePeers** - Configure peer relationships (hub→spoke)
2. **02_SetLibraries** - Set LayerZero libraries (TWICE: hub, then spoke)
3. **03-06_SetEnforcedOptions** - Set message gas/value parameters (3 contracts, any order)

### Verification - 2-3 Scripts
13. ✅ VerifyDeployment (Sepolia)
14. ✅ VerifyPeers (both chains)
15. ⭕ ShowTestnetAddresses (OP Sepolia)

---

## Post-Deployment Checklist

- [ ] All addresses documented in testnet.env
- [ ] All contracts verified on block explorers
- [ ] Bidirectional peers configured (iTRY, wiTRY, UnstakeMessenger)
- [ ] Enforced options set (3 contracts: ShareAdapter, ShareOFT, iTryAdapter)
  - UnstakeMessenger uses dynamic quoting with buffer instead of enforced options
- [ ] Verification scripts pass successfully
- [ ] Optional: Functional tests executed and passing
- [ ] Team notified of deployment completion
- [ ] Documentation updated with new addresses

---

## Environment Variables Reference

### Complete testnet.env Structure

After full deployment, your testnet.env should contain:

```bash
# RPC URLs
export SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"
export OP_SEPOLIA_RPC_URL="https://opt-sepolia.g.alchemy.com/v2/YOUR_KEY"

# API Keys
export ETHERSCAN_API_KEY="YOUR_SEPOLIA_KEY"
export OP_ETHERSCAN_API_KEY="YOUR_OP_SEPOLIA_KEY"

# Deployment Key
export DEPLOYER_PRIVATE_KEY="0x..."
export DEPLOYER_ADDRESS="0x..."

# Hub Chain (Sepolia) - Phase 1 Contracts
export HUB_ORACLE="0x..."
export HUB_DLF_TOKEN="0x..."
export HUB_ITRY_TOKEN="0x..."
export HUB_CUSTODIAN="0x..."
export HUB_CONTROLLER="0x..."
export HUB_BUFFER_POOL="0x..."
export HUB_STAKING="0x..."                    # ComposerStakedUSDeV2
export HUB_YIELD_DISTRIBUTOR="0x..."
export USDE_CROSSCHAIN_SILO="0x..."
export HUB_ITRY_ADAPTER="0x..."
export HUB_SHARE_ADAPTER="0x..."
export VAULT_COMPOSER="0x..."                 # VaultComposer (OApp)
export HUB_CHAIN_EID=40161

# Spoke Chain (OP Sepolia) - Phase 2 Contracts
export SPOKE_ITRY_OFT="0x..."
export SPOKE_SHARE_OFT="0x..."
export UNSTAKE_MESSENGER="0x..."              # UnstakeMessenger
export SPOKE_CHAIN_EID=40232

# Actor Addresses (Optional)
export TREASURY_ADDRESS="0x..."
export CEX_ADDRESS="0x..."
export DEX_ADDRESS="0x..."
export STAKER1_ADDRESS="0x..."
export REDEEMER_ADDRESS="0x..."
```

### Variable Name Guidelines

**IMPORTANT: Use these exact variable names throughout deployment:**

| Contract | Variable Name | Notes |
|----------|---------------|-------|
| ComposerStakedUSDeV2 | `HUB_STAKING` | NOT "COMPOSER_STAKED_USDE_V2" |
| VaultComposer | `VAULT_COMPOSER` | NOT "VAULT_COMPOSER_OAPP" |
| UnstakeMessenger | `UNSTAKE_MESSENGER` | NOT "SPOKE_UNSTAKE_MESSENGER" |
| USDeCrosschainSilo | `USDE_CROSSCHAIN_SILO` | Auto-deployed with StakedUSDeV2 |

---

## Quick Reference Commands

```bash
# Source environment
source testnet.env

# Check balances
cast balance $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC_URL
cast balance $DEPLOYER_ADDRESS --rpc-url $OP_SEPOLIA_RPC_URL

# Verify contract on Etherscan (Sepolia)
forge verify-contract $CONTRACT_ADDRESS <ContractName> \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# Verify contract on Etherscan (OP Sepolia)
forge verify-contract $CONTRACT_ADDRESS <ContractName> \
  --chain-id 11155420 \
  --verifier-url https://api-sepolia-optimistic.etherscan.io/api \
  --etherscan-api-key $OP_ETHERSCAN_API_KEY \
  --watch

# Verify with constructor arguments
forge verify-contract $CONTRACT_ADDRESS <ContractName> \
  --chain-id 11155111 \
  --constructor-args $(cast abi-encode "constructor(address,address)" $ARG1 $ARG2) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# Check peer configuration (after 01_ConfigurePeers)
cast call $HUB_ITRY_ADAPTER "peers(uint32)(bytes32)" $SPOKE_CHAIN_EID \
  --rpc-url $SEPOLIA_RPC_URL

# Check enforced options (after 04_SetEnforcedOptionsUnstakeMessenger)
cast call $UNSTAKE_MESSENGER "enforcedOptions(uint32,uint16)(bytes)" 40161 1 \
  --rpc-url $OP_SEPOLIA_RPC_URL

# Monitor LayerZero messages
# Visit: https://testnet.layerzeroscan.com/

# Check deployment registry
cat broadcast/deployment-addresses.json
```

---

**End of Deployment Checklist**

For detailed architecture and specifications, see:
- `/docs/architecture/DEPLOYMENT_GUIDE.md`
- `/developmentContext/smartContractDevelopmentContext/iTRY_System_Specification.md`
