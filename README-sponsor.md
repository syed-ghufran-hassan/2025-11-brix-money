# iTry Protocol - Smart Contracts

A cross-chain stablecoin protocol with yield-bearing staking functionality using LayerZero for cross-chain messaging.

## Overview

The iTry protocol consists of:

- **iTry Token**: Core stablecoin with minting/redemption mechanisms
- **wiTRY (StakediTry)**: ERC4626 vault for staking iTry and earning protocol yield
- **Cross-chain Support**: Hub and spoke chain architecture via LayerZero
- **Fast Redemption**: Instant redemption mechanism with cooldown periods
- **Yield Distribution**: NAV-based yield forwarding from LST and perpetual protocols

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git with submodules

## Installation

```bash
# Clone the repository with submodules
git clone --recursive https://github.com/your-org/iTry-contracts.git
cd iTry-contracts

# Install dependencies
make install

# Copy and configure environment variables
cp .env.example .env
# Edit .env with your RPC URLs
```

## Build & Test

```bash
# Build all contracts
make build

# Fast build (skips scripts - much faster for development)
make build-fast

# Run tests
make test

# Fast test
make test-fast

# Run tests with custom fuzz runs
make testFuzz 10000

# Generate coverage report
make report-cov

# Check contract sizes
make check-size
```

## Development

```bash
# Format code
make fmt

# Clean build artifacts
make clean

# View all available commands
make help
```

## Deployment

### Testnet Deployment

1. **Configure environment:**

   ```bash
   cp .env.example .env
   # Add your RPC URLs and private keys to .env
   ```

2. **Deploy to Sepolia (Test Hub Chain):**

   ```bash
   make deploy-sepolia
   ```

3. **Deploy to OP Sepolia (Test Spoke Chain):**

   ```bash
   make deploy-spoke-op-sepolia
   ```

4. **Configure cross-chain peers:**

   ```bash
   make configure-peers
   ```

5. **Verify deployments:**
   ```bash
   make verify-sepolia
   make verify-op-sepolia
   ```

## Architecture

```
src/
├── protocol/           # Core protocol contracts
│   ├── iTryIssuer.sol     # Minting/redemption logic
│   ├── FastAccessVault.sol # Instant redemption vault
│   └── YieldForwarder.sol  # Yield distribution
├── token/
│   └── wiTRY/          # Staking contracts
│       ├── StakediTry.sol         # ERC4626 staking vault
│       ├── StakediTryCrosschain.sol # Fast redemption logic
│       └── crosschain/            # LayerZero integration
└── utils/              # Common utilities
```

## Key Features

- **ERC4626 Staking**: Standard compliant yield-bearing vault
- **Cross-chain Transfers**: Bridge and deposit iTry/wiTRY between cains
- **Fast Redemption**: Instant withdrawals via cooldown mechanism
- **Yield Optimization**: Automated yield forwarding from underlying protocols
- **Access Control**: Role-based permissions for protocol operations

## Security

- Role-based access control for critical functions
- Reentrancy protection on state-changing operations
- Comprehensive test coverage

## License

MIT- See [LICENSE](./LICENSE)
