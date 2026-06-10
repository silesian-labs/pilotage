#!/usr/bin/env bash
# setup-vault.sh — one-shot demo environment setup
#
# Run this ONCE after deploying contracts (forge script Deploy.s.sol).
# It will:
#   1. Create a vault for the deployer captain
#   2. Register ConservativeRWA pilot in PilotRegistry (if not already registered)
#   3. Hire the pilot in the vault with a demo charter
#   4. Approve + deposit USDC into the vault
#
# Prerequisites:
#   - Contracts deployed, addresses in .env
#   - DEPLOYER has Arbitrum Sepolia USDC (get from https://app.aave.com/faucet/)
#   - PILOT_PRIVATE_KEY set (can be the same as PRIVATE_KEY for demo)
#
# Usage: ./scripts/setup-vault.sh [deposit_usdc_amount]
#   deposit_usdc_amount : USDC units (6 decimals), default 100000000 = 100 USDC

set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

: "${RPC:?Set RPC in .env}"
: "${PRIVATE_KEY:?Set PRIVATE_KEY in .env}"
: "${DEPLOYER_ADDRESS:?Set DEPLOYER_ADDRESS in .env}"
: "${VAULT_FACTORY:?Set VAULT_FACTORY in .env}"
: "${PILOT_REGISTRY:?Set PILOT_REGISTRY in .env}"
: "${CONSERVATIVE_RWA:?Set CONSERVATIVE_RWA in .env}"
: "${USDC_ADDRESS:?Set USDC_ADDRESS in .env}"
: "${AAVE_POOL:?Set AAVE_POOL in .env}"
: "${A_USDC_ADDRESS:?Set A_USDC_ADDRESS in .env}"

PILOT_ADDR="${PILOT_ADDRESS:-$DEPLOYER_ADDRESS}"
DEPOSIT_AMOUNT="${1:-10000000}"    # default: 10 USDC (6 decimals)
DEPOSIT_USDC=$(python3 -c "print(f'{$DEPOSIT_AMOUNT / 1e6:.2f}')" 2>/dev/null || echo "$DEPOSIT_AMOUNT raw units")

echo "=== Pilotage Demo Setup ==="
echo "Captain   : $DEPLOYER_ADDRESS"
echo "Pilot     : $PILOT_ADDR"
echo "Factory   : $VAULT_FACTORY"
echo "Registry  : $PILOT_REGISTRY"
echo "Deposit   : $DEPOSIT_USDC USDC"
echo ""

# ── 1. Check USDC balance ─────────────────────────────────────────────────────

USDC_BAL=$(cast call "$USDC_ADDRESS" \
  "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" \
  --rpc-url "$RPC")

echo "Your USDC balance: $USDC_BAL (raw)"

if [ "$USDC_BAL" = "0" ]; then
  echo ""
  echo "ERROR: No USDC in deployer wallet."
  echo "Get test USDC from: https://app.aave.com/faucet/ (select USDC, Arbitrum Sepolia)"
  exit 1
fi

# ── 2. Create vault ───────────────────────────────────────────────────────────

echo ""
echo "1/5 Creating vault..."

EXISTING_VAULT=$(cast call "$VAULT_FACTORY" \
  "vaultOf(address)(address)" "$DEPLOYER_ADDRESS" \
  --rpc-url "$RPC")

if [ "$EXISTING_VAULT" != "0x0000000000000000000000000000000000000000" ]; then
  echo "  Vault already exists: $EXISTING_VAULT"
  VAULT_ADDRESS="$EXISTING_VAULT"
else
  TX=$(cast send "$VAULT_FACTORY" \
    "createVault()(address)" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC" \
    --json)

  VAULT_ADDRESS=$(echo "$TX" | python3 -c "
import sys, json
receipt = json.load(sys.stdin)
# VaultCreated event topic: keccak256('VaultCreated(address,address,uint256)')
for log in receipt.get('logs', []):
    if len(log.get('topics', [])) >= 3:
        # vault is the second indexed topic (topics[2])
        raw = log['topics'][2]
        # strip leading zeros, add 0x prefix
        addr = '0x' + raw[-40:]
        print(addr)
        break
" 2>/dev/null || echo "")

  if [ -z "$VAULT_ADDRESS" ]; then
    # Fallback: read vaultOf after tx
    VAULT_ADDRESS=$(cast call "$VAULT_FACTORY" \
      "vaultOf(address)(address)" "$DEPLOYER_ADDRESS" \
      --rpc-url "$RPC")
  fi

  echo "  Vault created: $VAULT_ADDRESS"
fi

echo ""
echo "  Add to .env: VAULT_ADDRESS=$VAULT_ADDRESS"

# ── 3. Register pilot in PilotRegistry (if not already) ──────────────────────

echo ""
echo "2/5 Registering ConservativeRWA pilot..."

MIN_STAKE="5000000"

USDC_ALLOWANCE=$(cast call "$USDC_ADDRESS" \
  "allowance(address,address)(uint256)" "$DEPLOYER_ADDRESS" "$PILOT_REGISTRY" \
  --rpc-url "$RPC")

if [ "$USDC_ALLOWANCE" = "0" ]; then
  cast send "$USDC_ADDRESS" \
    "approve(address,uint256)" "$PILOT_REGISTRY" "$MIN_STAKE" \
    --private-key "$PRIVATE_KEY" \
    --rpc-url "$RPC" > /dev/null
  echo "  Approved USDC for registry"
fi

# Check if pilot is already registered by checking activePilotCount before/after
# We use a simple try: registerPilot will revert if executor already registered
# registerPilot(card, executor, operator, stake) — operator is the pilot runtime wallet
cast send "$PILOT_REGISTRY" \
  "registerPilot((string,string,string,string,address[]),address,address,uint256)" \
  '("ConservativeRWA","Maintains USDC/aUSDC target allocation via Aave V3","conservative","",['$CONSERVATIVE_RWA'])' \
  "$CONSERVATIVE_RWA" \
  "$PILOT_ADDR" \
  "$MIN_STAKE" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC" 2>/dev/null \
  && echo "  Pilot registered" \
  || echo "  Pilot already registered (skipped)"

# ── 4. Hire pilot in vault ────────────────────────────────────────────────────

echo ""
echo "3/5 Hiring pilot in vault..."

# Charter struct (single arg): pilot, allowedTargets, allowedTokensIn,
# allowedTokensOut, maxSingleAmountIn, maxDailyAmountIn, expiresAt.
# Both USDC and aUSDC allowed in/out so the pilot can supply AND withdraw.
EXPIRES_AT=$(( $(date +%s) + 604800 ))   # now + 7 days
MAX_SINGLE="10000000"                    # 10 USDC per action
MAX_DAILY="20000000"                     # 20 USDC per day

cast send "$VAULT_ADDRESS" \
  "hirePilot((address,address[],address[],address[],uint256,uint256,uint256))" \
  "($PILOT_ADDR,[$AAVE_POOL],[$USDC_ADDRESS,$A_USDC_ADDRESS],[$USDC_ADDRESS,$A_USDC_ADDRESS],$MAX_SINGLE,$MAX_DAILY,$EXPIRES_AT)" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC"

echo "  Pilot hired. Charter expires: $(date -d @$EXPIRES_AT 2>/dev/null || date -r $EXPIRES_AT)"

# ── 5. Deposit USDC into vault ────────────────────────────────────────────────

echo ""
echo "4/5 Approving USDC for vault deposit..."

cast send "$USDC_ADDRESS" \
  "approve(address,uint256)" "$VAULT_ADDRESS" "$DEPOSIT_AMOUNT" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC" > /dev/null

echo "5/5 Depositing $DEPOSIT_USDC USDC into vault..."

cast send "$VAULT_ADDRESS" \
  "deposit(address,uint256)" \
  "$USDC_ADDRESS" "$DEPOSIT_AMOUNT" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Add to .env:"
echo "  VAULT_ADDRESS=$VAULT_ADDRESS"
echo ""
echo "Start the pilot:   npm run dev --prefix pilot-runtime"
echo "Start the indexer: npm run dev --prefix indexer"
echo "Trigger rebalance: ./scripts/trigger-price-drop.sh up"
