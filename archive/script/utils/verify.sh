#!/usr/bin/env bash
# Helper script: interactive wrapper around `script/utils/verify.s.sol`.
# It loads variables from .env (if present) and then prompts for contract
# addresses, forwarding everything to the Forge verification script so
# you don't have to export env vars manually.

set -euo pipefail

# -----------------------------------------------------------------------------
# 0. Load variables from .env (if present) so API keys & RPC_URL are available
# -----------------------------------------------------------------------------
if [[ -f .env ]]; then
  # Export everything that's defined after sourcing
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Detect current chainId using `cast` if available, fallback to 0
DEFAULT_CHAIN_ID=$( (cast chain-id 2>/dev/null) || echo 0 )

printf "\n=== Charter Verification Helper ===\n"
read -rp "Chain ID [default ${DEFAULT_CHAIN_ID}]: " CHAIN_ID
CHAIN_ID=${CHAIN_ID:-$DEFAULT_CHAIN_ID}

read -rp "CharteredFundImplementation address: " CHARTER_IMPL
read -rp "UpgradeableBeacon address: " CHARTER_BEACON
read -rp "Foundation implementation address: " FOUNDATION_IMPL
read -rp "Foundation proxy (ERC1967) address: " FOUNDATION_PROXY
read -rp "Deployer (beacon owner) address: " DEPLOYER

printf "\nRunning verification script...\n\n"

# Capture Forge script output
forge_output=$(CHAIN_ID=$CHAIN_ID \
CHARTER_IMPL=$CHARTER_IMPL \
CHARTER_BEACON=$CHARTER_BEACON \
FOUNDATION_IMPL=$FOUNDATION_IMPL \
FOUNDATION_PROXY=$FOUNDATION_PROXY \
DEPLOYER=$DEPLOYER \
forge script script/utils/verify.s.sol -vvvv "$@" 2>&1)

# Echo the script logs to the user
printf "%s\n" "$forge_output"

# -----------------------------------------------------------------------------
# 1. Extract and execute verification commands
# -----------------------------------------------------------------------------
printf "\nExecuting verification commands...\n\n"
# Using awk to find lines that start with optional whitespace then 'forge verify-contract'
printf "%s\n" "$forge_output" | awk '/^[[:space:]]*forge verify-contract/ {print $0}' | while read -r cmd; do
  echo "→ $cmd"
  # shellcheck disable=SC2086
  eval $cmd
  echo "-------------------------------------------------------------"
  sleep_interval=5  # seconds pause between verification commands
  sleep $sleep_interval
done
