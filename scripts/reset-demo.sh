#!/usr/bin/env bash
# reset-demo.sh — resets vault state between demo runs
# Run before each live demo or recording session.
#
# What it does:
#   1. Withdraws all tokens from vault back to deployer
#   2. Resets oracle prices to starting values
#   3. Confirms vault is empty and ready for fresh deposit
#
# Usage: ./scripts/reset-demo.sh

set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

: "${RPC:?Set RPC in .env}"
: "${PRIVATE_KEY:?Set PRIVATE_KEY in .env}"
: "${VAULT_ADDRESS:?Set VAULT_ADDRESS in .env}"
: "${ORACLE_ADDRESS:?Set ORACLE_ADDRESS in .env}"
: "${USDC_ADDRESS:?Set USDC_ADDRESS in .env}"
: "${A_USDC_ADDRESS:?Set A_USDC_ADDRESS in .env}"
: "${DEPLOYER_ADDRESS:?Set DEPLOYER_ADDRESS in .env}"

CAST="cast"

echo "=== Pilotage Demo Reset ==="
echo "Vault  : $VAULT_ADDRESS"
echo "Chain  : $(cast chain-id --rpc-url $RPC)"
echo ""

# ── 1. Read current balances ──────────────────────────────────────────────────

USDC_BAL=$(cast call "$USDC_ADDRESS" \
  "balanceOf(address)(uint256)" "$VAULT_ADDRESS" \
  --rpc-url "$RPC" | cut -d' ' -f1)

AUSDC_BAL=$(cast call "$A_USDC_ADDRESS" \
  "balanceOf(address)(uint256)" "$VAULT_ADDRESS" \
  --rpc-url "$RPC" | cut -d' ' -f1)

echo "Current vault balances:"
echo "  USDC  : $USDC_BAL"
echo "  aUSDC : $AUSDC_BAL"
echo ""

# ── 2. Withdraw USDC if any ───────────────────────────────────────────────────

if [ "$USDC_BAL" != "0" ]; then
  echo "Withdrawing $USDC_BAL USDC..."
  cast send "$VAULT_ADDRESS" \
    "withdraw(address,uint256,address)" \
    "$USDC_ADDRESS" "$USDC_BAL" "$DEPLOYER_ADDRESS" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC"
  echo "  ✓ USDC withdrawn"
fi

# ── 3. Withdraw aUSDC if any ──────────────────────────────────────────────────

if [ "$AUSDC_BAL" != "0" ]; then
  echo "Withdrawing $AUSDC_BAL aUSDC..."
  cast send "$VAULT_ADDRESS" \
    "withdraw(address,uint256,address)" \
    "$A_USDC_ADDRESS" "$AUSDC_BAL" "$DEPLOYER_ADDRESS" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC"
  echo "  ✓ aUSDC withdrawn"
fi

# ── 4. Reset oracle prices to demo starting values ────────────────────────────

echo ""
echo "Resetting oracle prices..."

cast send "$ORACLE_ADDRESS" \
  "setPrice(address,uint256,string)" \
  "$USDC_ADDRESS" "1000000000000000000" "USDC" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC"

echo "  ✓ USDC = \$1.00"

cast send "$ORACLE_ADDRESS" \
  "setPrice(address,uint256,string)" \
  "$A_USDC_ADDRESS" "1000000000000000000" "aUSDC" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC"

echo "  ✓ aUSDC = \$1.00"

# ── 5. Verify vault is empty ──────────────────────────────────────────────────

echo ""
echo "Verifying vault is empty..."

USDC_AFTER=$(cast call "$USDC_ADDRESS" \
  "balanceOf(address)(uint256)" "$VAULT_ADDRESS" \
  --rpc-url "$RPC" | cut -d' ' -f1)

AUSDC_AFTER=$(cast call "$A_USDC_ADDRESS" \
  "balanceOf(address)(uint256)" "$VAULT_ADDRESS" \
  --rpc-url "$RPC" | cut -d' ' -f1)

echo "  USDC  : $USDC_AFTER"
echo "  aUSDC : $AUSDC_AFTER"

if [ "$USDC_AFTER" = "0" ] && [ "$AUSDC_AFTER" = "0" ]; then
  echo "  ✓ Vault empty"
else
  echo "  ⚠ Vault still has tokens. Check manually."
fi

# ── 6. Re-deposit USDC into vault ────────────────────────────────────────────

DEPOSIT_AMOUNT="${1:-10000000}"

echo ""
echo "Re-depositing $DEPOSIT_AMOUNT USDC into vault..."

cast send "$USDC_ADDRESS" \
  "approve(address,uint256)" "$VAULT_ADDRESS" "$DEPOSIT_AMOUNT" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC" > /dev/null

cast send "$VAULT_ADDRESS" \
  "deposit(address,uint256)" "$USDC_ADDRESS" "$DEPOSIT_AMOUNT" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC" > /dev/null

echo "  ✓ Deposited $DEPOSIT_AMOUNT USDC"

# ── 7. Clear indexer action history ──────────────────────────────────────────

echo ""
echo "Clearing indexer DB..."

if [ -z "${DATABASE_URL:-}" ]; then
  echo "  ⚠ DATABASE_URL not set — skipping DB clear"
else
  node --input-type=module <<EOF 2>&1
import postgres from '$(cd "$(dirname "$0")/.." && pwd)/indexer/node_modules/postgres/src/index.js';
const sql = postgres('${DATABASE_URL}', { onnotice: () => {} });
const result = await sql\`DELETE FROM actions\`;
console.log('  ✓ Actions cleared');
await sql.end();
EOF
fi

echo ""
echo "=== Reset complete. Start pilot and indexer, then trigger a rebalance. ==="
