#!/usr/bin/env bash
# trigger-rebalance.sh — simulates a market event to trigger the pilot
#
# Moves the aUSDC oracle price so the 50/50 vault crosses the 5% (500 bps)
# drift threshold and the pilot rebalances on its next tick. The moves are
# deliberately exaggerated (this is a mock oracle) so the threshold is clearly
# crossed during a live demo — real aUSDC tracks USDC ~1:1.
#
# Scenarios:
#   up    — aUSDC marked up to $1.40 → aUSDC overweight → pilot withdraws from Aave
#   depeg — aUSDC marked down to $0.70 → aUSDC underweight → pilot supplies to Aave
#   reset — restore both prices to $1.00
#
# Usage: ./scripts/trigger-price-drop.sh [up|depeg|reset]

set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

: "${RPC:?Set RPC in .env}"
: "${PRIVATE_KEY:?Set PRIVATE_KEY in .env}"
: "${ORACLE_ADDRESS:?Set ORACLE_ADDRESS in .env}"
: "${USDC_ADDRESS:?Set USDC_ADDRESS in .env}"
: "${A_USDC_ADDRESS:?Set A_USDC_ADDRESS in .env}"

SCENARIO="${1:-up}"

case "$SCENARIO" in
  up)
    # aUSDC marked up → vault overweight aUSDC → pilot withdraws to rebalance
    AUSDC_PRICE="1400000000000000000"   # $1.40
    LABEL="aUSDC marked up to \$1.40"
    ;;
  depeg)
    # aUSDC marked down → vault underweight aUSDC → pilot supplies to rebalance
    AUSDC_PRICE="700000000000000000"    # $0.70
    LABEL="aUSDC marked down to \$0.70"
    ;;
  reset)
    echo "Resetting oracle to \$1.00 / \$1.00..."
    cast send "$ORACLE_ADDRESS" \
      "setPrice(address,uint256,string)" \
      "$USDC_ADDRESS" "1000000000000000000" "USDC" \
      --private-key "$PRIVATE_KEY" --rpc-url "$RPC"
    cast send "$ORACLE_ADDRESS" \
      "setPrice(address,uint256,string)" \
      "$A_USDC_ADDRESS" "1000000000000000000" "aUSDC" \
      --private-key "$PRIVATE_KEY" --rpc-url "$RPC"
    echo "Done: USDC=\$1.00, aUSDC=\$1.00"
    exit 0
    ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Usage: $0 [up|depeg|reset]"
    exit 1
    ;;
esac

echo "=== Pilotage Demo: $LABEL ==="
echo "Oracle : $ORACLE_ADDRESS"
echo ""

cast send "$ORACLE_ADDRESS" \
  "setPrice(address,uint256,string)" \
  "$A_USDC_ADDRESS" "$AUSDC_PRICE" "aUSDC" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC"

echo "Done. The pilot will detect drift on its next tick (~${POLL_INTERVAL_MS:-15000}ms)."
echo "Watch pilot logs or: curl http://localhost:3001/api/vaults/\$VAULT_ADDRESS/actions"
