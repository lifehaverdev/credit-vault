#!/usr/bin/env bash
# Audits Foundation's protocolOwned accounting for corruption caused by the
# pre-fix _allocate/_remit bugs. Queries Donation, RemittanceProcessed, and
# CommitmentConfirmed events, then reads the current custody slot and prints
# the exact recoverProtocolOwned amount needed per token.
#
# Requires: cast (Foundry), python3, an archive-capable RPC endpoint.
#
# Usage:
#   FOUNDATION_PROXY=0x... bash script/utils/auditProtocolOwned.sh
#   # or rely on .env:
#   bash script/utils/auditProtocolOwned.sh

set -euo pipefail

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

PROXY="${FOUNDATION_PROXY:-0x01152530028bd834EDbA9744885A882D025D84F6}"
RPC="${RPC_URL:?RPC_URL must be set (archive node required)}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ""
echo "=== Foundation protocolOwned Audit ==="
echo "Proxy: $PROXY"
echo ""

# ── 1. Donation events ────────────────────────────────────────────────────────
echo "Fetching Donation events..."
cast logs \
  --rpc-url "$RPC" \
  --address "$PROXY" \
  --from-block earliest \
  --json \
  "Donation(address indexed funder, address indexed token, uint256 amount, bool isNFT, bytes32 metadata)" \
  > "$TMP/donations.json" 2>/dev/null || echo "[]" > "$TMP/donations.json"

python3 - "$TMP/donations.json" <<'PYEOF'
import json, sys

ETH = "0x0000000000000000000000000000000000000000"

with open(sys.argv[1]) as f:
    logs = json.load(f)

totals = {}
print(f"  {len(logs)} donation event(s):")
for log in sorted(logs, key=lambda l: int(l["blockNumber"], 16)):
    # topics[1]=funder(indexed), topics[2]=token(indexed)
    token = "0x" + log["topics"][2][-40:]
    # data: abi.encode(uint256 amount, bool isNFT, bytes32 metadata)
    data  = bytes.fromhex(log["data"][2:])
    amount = int.from_bytes(data[0:32], "big")
    label  = "ETH" if token == ETH else token
    totals[token] = totals.get(token, 0) + amount
    print(f"    block {int(log['blockNumber'],16):>8}  {label}  {amount} wei  ({amount/1e18:.6f})")

print()
print("  Totals donated by token:")
for token, total in totals.items():
    label = "ETH" if token == ETH else token
    print(f"    {label}: {total} wei  ({total/1e18:.6f})")

# Write totals for later comparison
with open("/tmp/_audit_totals.json", "w") as f:
    json.dump(totals, f)
PYEOF

# ── 2. Fee-carrying remits (_remit bug trigger) ───────────────────────────────
echo ""
echo "Fetching RemittanceProcessed events..."
cast logs \
  --rpc-url "$RPC" \
  --address "$PROXY" \
  --from-block earliest \
  --json \
  "RemittanceProcessed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata)" \
  > "$TMP/remits.json" 2>/dev/null || echo "[]" > "$TMP/remits.json"

python3 - "$TMP/remits.json" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    logs = json.load(f)

# data: abi.encode(uint256 amount, uint128 fee, bytes metadata)
fee_logs = []
for log in logs:
    data = bytes.fromhex(log["data"][2:])
    fee  = int.from_bytes(data[32:64], "big")
    if fee > 0:
        block = int(log["blockNumber"], 16)
        token = "0x" + log["topics"][3][-40:]
        fee_logs.append((block, token, fee))

if fee_logs:
    print(f"  ⚠ {len(fee_logs)} fee-carrying remit(s) found — _remit bug was triggered:")
    for block, token, fee in sorted(fee_logs):
        label = "ETH" if token == "0x" + "0"*40 else token
        print(f"    block {block:>8}  {label}  fee {fee} wei  ({fee/1e18:.6f})")
else:
    print("  No fee-carrying remits found — _remit bug not triggered.")
PYEOF

# ── 3. Allocate calls (_allocate bug trigger) ─────────────────────────────────
echo ""
echo "Fetching CommitmentConfirmed events (checking for allocate calls)..."
cast logs \
  --rpc-url "$RPC" \
  --address "$PROXY" \
  --from-block earliest \
  --json \
  "CommitmentConfirmed(address indexed fundAddress, address indexed user, address indexed token, uint256 amount, uint128 fee, bytes metadata)" \
  > "$TMP/commits.json" 2>/dev/null || echo "[]" > "$TMP/commits.json"

python3 - "$TMP/commits.json" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    logs = json.load(f)

# data: abi.encode(uint256 amount, uint128 fee, bytes metadata)
# metadata is a dynamic bytes — offset at byte 64, length at offset, data follows
allocates = []
for log in logs:
    data = bytes.fromhex(log["data"][2:])
    meta_offset = int.from_bytes(data[64:96], "big")
    meta_len    = int.from_bytes(data[meta_offset:meta_offset+32], "big")
    meta        = data[meta_offset+32 : meta_offset+32+meta_len]
    if meta == b"ALLOCATED":
        block  = int(log["blockNumber"], 16)
        amount = int.from_bytes(data[0:32], "big")
        token  = "0x" + log["topics"][3][-40:]
        allocates.append((block, token, amount))

if allocates:
    print(f"  ⚠ {len(allocates)} allocate call(s) found — _allocate bug was triggered:")
    for block, token, amount in sorted(allocates):
        label = "ETH" if token == "0x" + "0"*40 else token
        print(f"    block {block:>8}  {label}  {amount} wei  ({amount/1e18:.6f})")
else:
    print("  No allocate calls found — _allocate bug not triggered.")
PYEOF

# ── 4. Current custody slots ──────────────────────────────────────────────────
echo ""
echo "Reading current protocolOwned slots..."

# Collect all tokens seen in donations
TOKENS=$(python3 - "$TMP/donations.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    logs = json.load(f)
tokens = set()
for log in logs:
    tokens.add("0x" + log["topics"][2][-40:])
print("\n".join(tokens))
PYEOF
)

if [[ -z "$TOKENS" ]]; then
    echo "  No donation events found — nothing to recover."
    exit 0
fi

PROXY_HEX=$(echo "$PROXY" | tr '[:upper:]' '[:lower:]' | sed 's/0x//')

echo "$TOKENS" | while read -r TOKEN; do
    TOKEN_HEX=$(echo "$TOKEN" | tr '[:upper:]' '[:lower:]' | sed 's/0x//')
    # keccak256(abi.encodePacked(address proxy, address token))
    KEY=$(cast keccak "0x${PROXY_HEX}${TOKEN_HEX}")
    SLOT=$(cast call "$PROXY" "custody(bytes32)(bytes32)" "$KEY" --rpc-url "$RPC" 2>/dev/null || echo "0x0")

    python3 - "$SLOT" "$TOKEN" "/tmp/_audit_totals.json" <<'PYEOF'
import json, sys

slot  = int(sys.argv[1], 16)
token = sys.argv[2].lower()
owned  = slot & ((1 << 128) - 1)
escrow = (slot >> 128) & ((1 << 128) - 1)
ETH    = "0x" + "0"*40
label  = "ETH" if token == ETH else token

with open(sys.argv[3]) as f:
    totals = json.load(f)

total_donated = totals.get(token, 0)
recovery      = max(0, total_donated - owned)

print(f"  {label}:")
print(f"    protocolOwned  (current):  {owned} wei  ({owned/1e18:.6f})")
print(f"    protocolEscrow (current):  {escrow} wei  ({escrow/1e18:.6f})")
print(f"    total donated:             {total_donated} wei  ({total_donated/1e18:.6f})")
if recovery > 0:
    print(f"    *** RECOVERY NEEDED:       {recovery} wei  ({recovery/1e18:.6f}) ***")
    print(f"    call: recoverProtocolOwned({sys.argv[2]}, {recovery})")
else:
    print(f"    No recovery needed.")
PYEOF
done

echo ""
echo "Done."
