# Crosschain Tests

This directory contains tests for the iTRY crosschain functionality, including composer-based cooldowns and LayerZero-based unstaking.

## Test Structure

### Unit Tests (✅ All Passing)

#### `StakediTryCrosschain.t.sol` - 28 tests

Tests the StakediTryCrosschain contract functionality on the hub chain:

- Constructor and setup
- COMPOSER_ROLE management (grant/revoke)
- `cooldownSharesByComposer()` - composer initiates cooldown for redeemer
- `cooldownAssetsByComposer()` - asset-based cooldown initiation
- `unstakeThroughComposer()` - unstake after cooldown completion
- Error handling and access control
- Integration with standard cooldown functions

**Key Features Tested:**

- Composer can burn shares and assign cooldown to redeemer
- Multiple cooldowns accumulate correctly
- Standard users unaffected by composer functions
- Proper role-based access control

#### `crosschain/UnstakeMessenger.t.sol` - 45 tests

Comprehensive unit tests for the UnstakeMessenger contract on spoke chains:

- Constructor validation
- `unstake()` function with fee handling
- `quoteUnstake()` and `quoteUnstakeWithBuffer()` fee calculation
- Peer management (setPeer, getPeer)
- Rescue functions (ERC20/ETH)
- Security tests (reentrancy, user validation)
- Edge cases (zero fees, max fees, multiple unstakes)
- Integration flow validation

**Key Features Tested:**

- User initiates unstake from spoke chain
- Fee calculation with buffer mechanism
- Message encoding for crosschain communication
- LayerZero integration points

#### `crosschain/VaultComposerStructDecoding.t.sol` - 5 tests

Tests for ABI encoding/decoding fix (Panic(0x41) prevention):

- Direct struct decoding pattern (correct)
- Broken bytes decoding pattern (demonstrates bug)
- Fuzz tests with random users and options
- Validates fix for struct vs bytes decoding issue

**Purpose:**

- Documents and prevents regression of critical ABI decoding bug
- Ensures UnstakeMessage struct is properly decoded

---

## Crosschain Test Infrastructure

### `crosschain/CrossChainTestBase.sol` - Fork Testing Infrastructure

**Status:** ✅ Fully working with Alchemy RPC endpoints

Provides comprehensive fork-based testing infrastructure for crosschain operations:

**Features:**

- Fork management for Sepolia (hub) and OP Sepolia (spoke)
- LayerZero message capture and relay simulation
- Contract deployment helpers for both chains
- Peer configuration for all crosschain contracts
- Message decoding and routing

**Contracts Deployed:**

- **Sepolia (Hub):**

  - iTry (with ERC1967Proxy)
  - iTryTokenOFTAdapter
  - StakediTryCrosschain
  - wiTryVaultComposer
  - wiTryOFTAdapter

- **OP Sepolia (Spoke):**
  - iTryTokenOFT
  - wiTryOFT
  - UnstakeMessenger

**Peer Configuration:**

- iTryTokenOFTAdapter ↔ iTryTokenOFT
- wiTryOFTAdapter ↔ wiTryOFT
- wiTryVaultComposer ↔ UnstakeMessenger

**RPC Configuration:**

- Uses Alchemy RPC endpoints (configured in CrossChainTestBase.sol)
- Public Sepolia RPCs were unreliable; switched to Alchemy for stability
- Alternative RPC providers can be configured in `.env.testnet` for reference

**Running Fork Tests:**

```bash
forge test --match-path "test/crosschainTests/crosschain/CrossChainTestBase.t.sol"
```

---

## Disabled Integration Tests

The following integration tests are disabled pending CrossChainTestBase availability:

### Phase 3 Integration Tests (Ready to Enable)

Once CrossChainTestBase fork tests work, these can be enabled:

1. **`Step5_BasicOFTTransfer.t.sol`** - Basic iTRY bridging

   - L1→L2 and L2→L1 transfers
   - Supply conservation validation

2. **`Step6_VaultComposerTest.t.sol`** - wiTryVaultComposer tests

   - Deployment and configuration
   - Access control validation
   - Vault deposit flow

3. **`Step7_OVaultDeposit.t.sol`** - OVault main feature

   - L2→L1 crosschain vault deposits
   - Compose message handling
   - Share minting validation

4. **`Step8_ShareBridging.t.sol`** - Share token bridging

   - Bidirectional wiTRY transfers
   - Share supply conservation
   - Round-trip validation

5. **`CrosschainUnstake.t`** - Complete unstake flow

   - Cooldown initiation → unstake request → completion
   - Multi-user scenarios
   - Error handling

6. **`VaultComposerCrosschainUnstaking.t.sol`** - Unstake message handling

   - OApp integration validation
   - Message routing
   - Peer validation

7. **`Step3_DeploymentTest.t.sol`** - Deployment validation
8. **`Step4_MessageRelayTest.t.sol`** - Message relay infrastructure

---

## Test Coverage Summary

| Test Suite                        | Tests  | Status         | Coverage            |
| --------------------------------- | ------ | -------------- | ------------------- |
| StakediTryCrosschain.t.sol        | 28     | ✅ Passing     | Unit tests          |
| UnstakeMessenger.t.sol            | 45     | ✅ Passing     | Unit tests          |
| VaultComposerStructDecoding.t.sol | 5      | ✅ Passing     | Bug fix validation  |
| CrossChainTestBase.t.sol          | 3      | ✅ Passing     | Fork infrastructure |
| **Total Active**                  | **81** | **✅ Passing** | -                   |
| Integration tests                 | ~100+  | 🔒 Disabled    | Awaiting fork tests |

---

## Running Tests

### Run All Active Crosschain Tests

```bash
forge test --match-path "test/crosschainTests/**/*.sol"
```

### Run Specific Test Suites

```bash
# StakediTryCrosschain tests
forge test --match-path "test/crosschainTests/StakediTryCrosschain.t.sol"

# UnstakeMessenger tests
forge test --match-path "test/crosschainTests/crosschain/UnstakeMessenger.t.sol"

# Struct decoding tests
forge test --match-path "test/crosschainTests/crosschain/VaultComposerStructDecoding.t.sol"
```

### Run Fork Tests (when RPCs available)

```bash
# Requires working Sepolia and OP Sepolia RPCs
forge test --match-path "test/crosschainTests/crosschain/CrossChainTestBase.t.sol" -vvv
```

---

## Architecture Overview

### Crosschain Unstaking Flow

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Spoke Chain    │         │   LayerZero      │         │   Hub Chain     │
│  (OP Sepolia)   │         │                  │         │   (Sepolia)     │
└─────────────────┘         └──────────────────┘         └─────────────────┘

1. User holds wiTRY shares
   │
   v
2. User sends shares to UnstakeMessenger
   │
   v
3. UnstakeMessenger:
   - Burns shares (or sends to vault composer)
   - Encodes UnstakeMessage
   - Sends LZ message to hub
   │
   v
4. LayerZero relays message
   │
   v
5. wiTryVaultComposer receives message:
   - Validates user
   - Calls vault.unstakeThroughComposer(user)
   │
   v
6. StakediTryCrosschain:
   - Checks cooldown completion
   - Transfers iTRY from silo to composer
   │
   v
7. wiTryVaultComposer:
   - Sends iTRY back to user on spoke chain via LayerZero
```

### Contract Relationships

**Hub Chain (Sepolia):**

- `StakediTryCrosschain` - Vault with composer-managed cooldowns
- `wiTryVaultComposer` - Crosschain orchestrator
- `iTryTokenOFTAdapter` - iTRY crosschain adapter
- `wiTryOFTAdapter` - wiTRY share adapter

**Spoke Chain (OP Sepolia):**

- `UnstakeMessenger` - Initiates unstake requests
- `iTryTokenOFT` - iTRY representation
- `wiTryOFT` - wiTRY share representation

**Key Roles:**

- `COMPOSER_ROLE` - Granted to wiTryVaultComposer
- Allows burning shares and assigning cooldown to end user

---

## Configuration

### RPC Endpoints

Fork tests require RPC URLs to be configured via environment variables.

**Setup:**

1. Copy the example environment file:

   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and add your RPC URLs:

   ```bash
   SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
   OP_SEPOLIA_RPC_URL=https://opt-sepolia.g.alchemy.com/v2/YOUR_API_KEY
   ```

3. Foundry automatically loads `.env` when running tests

**Environment Variables:**

- `SEPOLIA_RPC_URL` - Sepolia (Ethereum testnet) RPC endpoint
- `OP_SEPOLIA_RPC_URL` - OP Sepolia (Optimism testnet) RPC endpoint

**Fallback Values:**
If environment variables are not set, tests will use hardcoded Alchemy endpoints with a shared API key (may hit rate limits).

**Recommended Providers:**

- **Alchemy** (recommended): `https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY`
- **Infura**: `https://sepolia.infura.io/v3/YOUR_API_KEY`
- **Public RPCs** (unreliable): `https://rpc.sepolia.org`, `https://sepolia.optimism.io`

**Note:** Public Sepolia RPCs have experienced timeout issues. Use API-key based providers (Alchemy/Infura) for reliable testing.

See `.env.example` and `.env.testnet` for reference configurations.

### LayerZero Configuration

**Endpoint IDs:**

- Sepolia: `40161`
- OP Sepolia: `40232`

**Endpoint Address:**

- Both chains: `0x6EDCE65403992e310A62460808c4b910D972f10f`

---

## Development Notes

### Test Adaptation History

1. **Phase 1** - Unit test adaptation (Completed ✅)

   - Adapted StakediTryCrosschain.t.sol to refactored contracts
   - Re-enabled UnstakeMessenger.t.sol
   - Re-enabled VaultComposerStructDecoding.t.sol
   - Fixed import paths (../../src/ → ../../../src/)
   - Updated to use proper iTry proxy deployment

2. **Phase 2** - Fork infrastructure (Completed ✅)

   - Updated CrossChainTestBase.sol
   - Added wiTryVaultComposer and UnstakeMessenger
   - Fixed constructor signatures
   - Configured crosschain peers
   - Code complete, awaiting RPC availability

3. **Phase 3** - Integration tests (Pending 🔒)
   - Awaiting fork test infrastructure
   - ~10 integration test files ready to adapt

### Known Issues

1. **Fork Test Performance** - Fork tests are slower than unit tests

   - Fork tests take ~600ms vs ~5ms for unit tests
   - Consider running fork tests separately from main test suite
   - Use `-vvv` for detailed debugging when needed

2. **RPC Dependency** - Tests depend on external RPC availability
   - Using Alchemy RPC endpoints (stable and reliable)
   - May encounter rate limiting with free tier API keys
   - Alternative: Use paid API keys or other providers (Infura, etc.)

---

## Contributing

When adding new crosschain tests:

1. **Unit tests** - Use mocks, no network dependencies
2. **Integration tests** - Extend CrossChainTestBase
3. **Follow naming conventions:**
   - `test_` prefix for test functions
   - Descriptive names: `test_unstake_revertsWhenCooldownNotReady`
4. **Update this README** with new test information

---

## References

- [LayerZero V2 Docs](https://docs.layerzero.network/)
- [iTRY System Specification](../../developmentContext/smartContractDevelopmentContext/iTRY_System_Specification.md)
- [Foundry Testing Guide](https://book.getfoundry.sh/forge/tests)
