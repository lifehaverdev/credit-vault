#!/bin/bash

###############################################################################
# run-with-env.sh
#
# Lightweight utility to run any command **with** the variables from the local
# .env file automatically exported – mimicking the logic inside run-dev.sh but
# generic for any command (migration scripts, one-off tasks, etc.).
#
# Usage examples:
#   ./run-with-env.sh node scripts/migrations/2025_07_add_spell_public_slug.js
#   ./run-with-env.sh node scripts/migrations/2025_07_seed_spell_public_slug.js --dry-run
#   ./run-with-env.sh bash -c 'echo "DB is $MONGO_DB_NAME"'
#
# Notes:
#   • No external dependencies (dotenv npm package not required)
#   • Supports quoted values and ignores commented / blank lines in .env
#   • Additional arguments are passed through unchanged.
###############################################################################

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <command> [args...]"
  exit 1
fi

# -----------------------------------------------------------------------------
# 1. Load variables from .env (if present)
# -----------------------------------------------------------------------------
if [ -f .env ]; then
  echo "[run-with-env.sh] Loading variables from .env"
  while IFS='=' read -r key value; do
    # Trim whitespace around key
    key="$(echo "$key" | xargs)"
    # Remove surrounding quotes from value (single or double)
    value="$(echo "$value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"

    # Skip if line is comment or blank
    if [[ -z "$key" || "$key" =~ ^# ]]; then
      continue
    fi

    # Only export if key is a valid shell variable name
    if [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      export "$key"="$value"
    fi
  done < <(grep -v '^\s*#' .env | grep '=')
else
  echo "[run-with-env.sh] No .env file found – continuing with existing environment"
fi

# -----------------------------------------------------------------------------
# 2. Execute the requested command
# -----------------------------------------------------------------------------

cmd=("$@")

echo "[run-with-env.sh] Executing: ${cmd[*]}" >&2
exec "${cmd[@]}" 