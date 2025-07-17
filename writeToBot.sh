#!/bin/bash

# Source environment variables
if [ -f .env ]; then
  source .env
else
  echo ".env file not found!"
  exit 1
fi

# Check if BOT_ABI_PATH is set
if [ -z "$BOT_ABI_PATH" ]; then
  echo "BOT_ABI_PATH is not set in .env"
  exit 1
fi

# Build contracts (optional, but ensures ABI is up to date)
forge build

# Write ABIs to the bot directory
forge inspect src/Foundation.sol:Foundation abi --json > "$BOT_ABI_PATH/foundation.json"
forge inspect src/CharteredFund.sol:CharteredFund abi --json > "$BOT_ABI_PATH/charteredFund.json"
# Write bytecode to the bot directory/bytecode
mkdir -p "$BOT_ABI_PATH/bytecode"
forge inspect src/Foundation.sol:Foundation bytecode --json > "$BOT_ABI_PATH/bytecode/foundation.bytecode.json"
forge inspect src/CharteredFund.sol:CharteredFund bytecode --json > "$BOT_ABI_PATH/bytecode/charteredFund.bytecode.json"

echo "ABIs written to $BOT_ABI_PATH and bytecode written to $BOT_ABI_PATH/bytecode"