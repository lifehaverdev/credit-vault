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

# Write ABI to the bot directory
forge inspect src/CreditVault.sol:CreditVault abi --json > "$BOT_ABI_PATH/creditVault.json"

echo "CreditVault ABI written to $BOT_ABI_PATH/creditVault.json"