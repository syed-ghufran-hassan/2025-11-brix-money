# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#                          Inverter Network Makefile
#
# WARNING: This file is part of the git repo. DO NOT INCLUDE SENSITIVE DATA!
#
# The Inverter Network smart contracts project uses this Makefile to execute 
# common tasks.
#
# The Makefile supports a help command, i.e. `make help`.
#
# Expected enviroment variables are defined in the `dev.env` file.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# This loads in the dev.env as the environment

ifneq (,$(wildcard ./dev.env))
    include dev.env
    export
endif

# -----------------------------------------------------------------------------
# Common
.PHONY: clean
clean: # Remove build artifacts
	@forge clean

.PHONY: install
install: # Installs the required dependencies
	@forge install

.PHONY: build
build: # Build project
	@forge build

.PHONY: build-fast
build-fast: # Build project WITHOUT scripts (much faster - skips via_ir)
	@echo "Building without scripts for fast compilation (using fast profile)..."
	@{ \
	trap 'mv .script/ script/; mv .MasterDeploymentScript.t.sol test/integration/MasterDeploymentScript.t.sol 2>/dev/null || true' EXIT; \
	mv script/ .script/; \
	mv test/integration/MasterDeploymentScript.t.sol .MasterDeploymentScript.t.sol 2>/dev/null || true; \
	export FOUNDRY_PROFILE=fast && forge build; \
	}

.PHONY: list-size
list-size: # Print the size of contracts
	@{ \
	trap 'mv .test/ test/; mv .script/ script/; mv .templates/ src/templates/' EXIT; \
	mv test/ .test/; \
	mv script/ .script/; \
	mv src/templates/ .templates/; \
	forge build --sizes; \
	}

.PHONY: check-size
check-size: # Checks the size of contracts
	@{ \
	trap 'mv .test/ test/; mv .script/ script/; mv .templates/ src/templates/' EXIT; \
	mv test/ .test/; \
	mv script/ .script/; \
	mv src/templates/ .templates/; \
	forge build --sizes | awk '!/----/ && /-[0-9]+/ { print; FOUND=1} END { if (!FOUND) { print "All contracts within the limit."; exit 0 }; if (FOUND) { exit 1 } }'; \
	}

.PHONY: update
update: # Update dependencies
	@forge update

.PHONY: test
test: # Run whole test suite
	@forge test -vvv

.PHONY: test-fast
test-fast: # Run tests WITHOUT compiling scripts (much faster)
	@echo "Running tests with fast compilation (skipping scripts, using fast profile)..."
	@{ \
	trap 'mv .script/ script/; mv .MasterDeploymentScript.t.sol test/integration/MasterDeploymentScript.t.sol 2>/dev/null || true' EXIT; \
	mv script/ .script/; \
	mv test/integration/MasterDeploymentScript.t.sol .MasterDeploymentScript.t.sol 2>/dev/null || true; \
	export FOUNDRY_PROFILE=fast && forge test -vv; \
	}

.PHONY: testFuzz
testFuzz: # Run whole test suite with a custom amount of fuzz runs
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" -ge 1 ] 2>/dev/null; then \
		export FOUNDRY_FUZZ_RUNS=$(filter-out $@,$(MAKECMDGOALS)); \
	else \
		read -p "Fuzz runs (no input = defaults to 1024): " RUNS; \
		export FOUNDRY_FUZZ_RUNS=$$(if [ "$$RUNS" -ge 1 ] 2>/dev/null; then echo $$RUNS; else echo 1024; fi); \
	fi; \
	if [ $$FOUNDRY_FUZZ_RUNS -gt 1024 ]; then \
		export FOUNDRY_FUZZ_MAX_TEST_REJECTS=$$((FOUNDRY_FUZZ_RUNS * 50)); \
	else \
		export FOUNDRY_FUZZ_MAX_TEST_REJECTS=65536; \
	fi; \
	echo "Running tests with $${FOUNDRY_FUZZ_RUNS} fuzz runs and $${FOUNDRY_FUZZ_MAX_TEST_REJECTS} accepted test rejections..."; \
	forge test -vvv

# -----------------------------------------------------------------------------
# Individual Component Tests

#.PHONY: testE2e
#testE2e: # Run e2e test suite
#	@make pre-test
#	@forge test -vvv --match-path "*/e2e/*"
#
.PHONY: testScripts
testScripts: # Run scripts
	@echo "### Run scripts"
	@if [ -n "$$SEPOLIA_RPC_URL" ]; then \
		echo "🔱 Forking from: $$SEPOLIA_RPC_URL"; \
		if [ -n "$$FORK_BLOCK_NUMBER" ]; then \
			echo "📦 Fork block number: $$FORK_BLOCK_NUMBER"; \
			FORK_ARGS="--fork-url $$SEPOLIA_RPC_URL --fork-block-number $$FORK_BLOCK_NUMBER"; \
		else \
			echo "📦 Forking from latest block"; \
			FORK_ARGS="--fork-url $$SEPOLIA_RPC_URL"; \
		fi; \
	else \
		echo "🆕 Running without fork"; \
		FORK_ARGS=""; \
	fi; \
	echo "Run MasterDeploymentScript"; \
	forge script script/MasterDeploymentScript.s.sol:MasterDeploymentScript $$FORK_ARGS

# -----------------------------------------------------------------------------
# Testnet Deployment

.PHONY: show-testnet-addresses
show-testnet-addresses: # Show all derived actor addresses for testnet funding
	@echo "Showing testnet addresses..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found. Copy testnet.env.example and fill in your keys."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/ShowTestnetAddresses.s.sol:ShowTestnetAddresses \
		--rpc-url $$SEPOLIA_RPC_URL

.PHONY: deploy-sepolia
deploy-sepolia: # Deploy to Sepolia testnet
	@echo "Deploying to Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found. Copy testnet.env.example and fill in your keys."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/MasterDeploymentScript.s.sol:MasterDeploymentScript \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--etherscan-api-key $$ETHERSCAN_API_KEY \
		-vvvv

.PHONY: deploy-spoke-op-sepolia
deploy-spoke-op-sepolia: # Deploy spoke contracts to OP Sepolia (L2)
	@echo "Deploying spoke contracts to OP Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found. Copy testnet.env.example and fill in your keys."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/SpokeChainDeployment.s.sol:SpokeChainDeployment \
		--rpc-url $$OP_SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--etherscan-api-key $$OP_ETHERSCAN_API_KEY \
		-vvvv

.PHONY: configure-peers
configure-peers: # Configure hub->spoke peer relationships on Sepolia
	@echo "Configuring peer relationships..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found. Copy testnet.env.example and fill in your keys."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/ConfigurePeers.s.sol:ConfigurePeers \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvv

.PHONY: verify-sepolia
verify-sepolia: # Verify deployment on Sepolia
	@echo "Verifying Sepolia deployment..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/VerifyDeployment.s.sol:VerifyDeployment \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		-vvv

.PHONY: verify-op-sepolia
verify-op-sepolia: # Verify deployment on OP Sepolia
	@echo "Verifying OP Sepolia deployment..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/VerifyDeployment.s.sol:VerifyDeployment \
		--rpc-url $$OP_SEPOLIA_RPC_URL \
		--broadcast \
		-vvv

# -----------------------------------------------------------------------------
# Testnet Testing Infrastructure

.PHONY: verify-peers-sepolia
verify-peers-sepolia: # Verify peer configuration on Sepolia
	@echo "Verifying peer configuration on Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/VerifyPeers.s.sol:VerifyPeers \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvv

.PHONY: verify-peers-op-sepolia
verify-peers-op-sepolia: # Verify peer configuration on OP Sepolia
	@echo "Verifying peer configuration on OP Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/VerifyPeers.s.sol:VerifyPeers \
		--rpc-url $$OP_SEPOLIA_RPC_URL \
		-vvv

.PHONY: test-bridge-sepolia-to-op
test-bridge-sepolia-to-op: # Test iTRY bridging from Sepolia to OP Sepolia (dry run)
	@echo "Testing bridge from Sepolia to OP Sepolia (dry run)..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/TestnetBridgeTest.s.sol:TestnetBridgeTest \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvv

.PHONY: validate-testnet
validate-testnet: # Run comprehensive testnet validation (hub chain)
	@echo "Running testnet validation on Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/TestnetE2EValidation.s.sol:TestnetE2EValidation \
		--rpc-url $$SEPOLIA_RPC_URL \
		-vvv

.PHONY: validate-testnet-spoke
validate-testnet-spoke: # Run testnet validation on spoke chain
	@echo "Running testnet validation on OP Sepolia..."
	@if [ ! -f testnet.env ]; then \
		echo "ERROR: testnet.env not found."; \
		exit 1; \
	fi
	@source testnet.env && forge script script/TestnetE2EValidation.s.sol:TestnetE2EValidation \
		--rpc-url $$OP_SEPOLIA_RPC_URL \
		-vvv

# -----------------------------------------------------------------------------
# Static Analyzers

.PHONY: analyze-slither
analyze-slither: # Run slither analyzer against project (requires solc-select)
	@forge build --extra-output abi --extra-output userdoc --extra-output devdoc --extra-output evm.methodIdentifiers
	@solc-select use 0.8.23
	@slither --ignore-compile src/common      || \
	slither --ignore-compile src/external     || \
	slither --ignore-compile src/factories    || \
	slither --ignore-compile src/modules      || \
	slither --ignore-compile src/orchestrator || \
	slither --ignore-compile src/proxies

.PHONY: analyze-c4udit
analyze-c4udit: # Run c4udit analyzer against project
	@c4udit src

# -----------------------------------------------------------------------------
# Reports

.PHONY: report-gas
report-gas: # Print gas report
	@forge test --gas-report

.PHONY: report-cov
report-cov: # Print coverage report (excludes crosschain fork tests that fail in coverage mode)
	@echo "### Running tests & generating the coverage report..."
	@forge coverage --ir-minimum --nmc "Step3_DeploymentTest|CrossChainTestBaseTest" --report lcov
	@genhtml lcov.info --branch-coverage --output-dir coverage
	@forge snapshot

# -----------------------------------------------------------------------------
# Formatting

.PHONY: fmt
fmt: # Format code
	@forge fmt

.PHONY: fmt-check
fmt-check: # Check whether code formatted correctly
	@forge fmt --check

# -----------------------------------------------------------------------------
# Git

pre-test: # format and export correct data
	@echo "### Formatting..."
	@forge fmt

	@echo "### Env variables to make sure the local tests runs"
	@echo "### equally long compared to the CI tests"
	@export FOUNDRY_FUZZ_RUNS=1024
	@export FOUNDRY_FUZZ_MAX_TEST_REJECTS=65536

.PHONY: pre-commit
pre-commit: # Git pre-commit hook
	@echo "### Checking the contract size"
	@make check-size
	
#	@echo "### Running the scripts"
#	@make testScripts

	@echo "### Configure tests"
	@make pre-test

	@echo "### Running the tests"
	@forge test

# -----------------------------------------------------------------------------
# Help Command

.PHONY: help
help: # Show help for each of the Makefile recipes
	@grep -E '^[a-zA-Z0-9 -]+:.*#'  Makefile | sort | while read -r l; do printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; done
