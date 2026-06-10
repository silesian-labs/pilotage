# Pilotage — Codebase Reference

## 1. Project Overview

Pilotage is a non-custodial DeFi vault platform that lets a **captain** (asset owner) deposit funds into a personal on-chain vault and delegate trading authority to an **AI pilot** — a permissioned autonomous agent — without ever surrendering custody. Each pilot's scope of action is strictly bounded by a signed **charter**: a whitelist of allowed contracts, tokens, and spending caps. A pilot cannot move funds outside those bounds regardless of what its off-chain logic attempts. Every successful execution is recorded as a positive reputation event on-chain via the ERC-8004 reputation standard, creating a verifiable track record for pilots across all vaults. The reference pilot, ConservativeRWA, uses Google Gemini to decide the size and timing of USDC/aUSDC rebalances on Aave V3 on Arbitrum Sepolia.

---

## 2. Architecture Diagram

```
  Captain (EOA)
      │
      │  createVault()       hirePilot(charter)
      ▼                      ▼
  ┌──────────────────────────────────────┐
  │           VaultFactory               │
  │  (ERC-1167 minimal proxy factory)    │
  │  deploys Vault clones                │
  └──────────────────┬───────────────────┘
                     │ clone
                     ▼
  ┌──────────────────────────────────────┐
  │                Vault                 │
  │  - charter storage per pilot         │◄──── Captain: deposit / withdraw /
  │  - CharterValidator (inline)         │      pause / forceWithdrawAll
  │  - reentrancy lock                   │
  │  - daily spend tracker               │
  └───────┬──────────────────────────────┘
          │ executePlan(actions[])
          │ called by Pilot Runtime
          ▼
  ┌───────────────────────────────────────┐
  │           CharterValidator            │
  │  checks: target whitelist,            │
  │  tokenIn/Out whitelist,               │
  │  maxSingleAmountIn, charter expiry    │
  └───────┬───────────────────────────────┘
          │ approved calls only
          ▼
  ┌───────────────────┐    ┌──────────────────────┐
  │   Aave V3 Pool    │    │   ERC-8004 Reputation │
  │  supply / withdraw│    │  postFeedback(+1)     │
  └───────────────────┘    └──────────────────────┘

  ┌────────────────────────────────────────────────────────────────┐
  │                      PilotRegistry                             │
  │  developer registers pilot (executor address + stake in USDC)  │
  │  owner can slash; developer can unregister and reclaim stake   │
  └────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │                     Pilot Runtime (Node.js)                  │
  │                                                              │
  │  Pilot (SDK) ──poll──► VaultClient.readState()              │
  │       │                  (balances, prices, charter)         │
  │       │                                                      │
  │       └──► Strategy.decide()                                 │
  │                 │                                            │
  │                 ├── computeDrifts() on ConservativeRWA       │
  │                 ├── shouldRebalance()                        │
  │                 └── decideWithGemini() ──► Gemini API        │
  │                           │                                  │
  │                           └── walletClient.writeContract()   │
  │                                 Vault.executePlan()          │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │                       Indexer (Hono + postgres)              │
  │                                                              │
  │  watchContractEvent:                                         │
  │    VaultFactory.VaultCreated  ──► vaults table               │
  │    PilotRegistry.PilotRegistered ──► pilots table            │
  │    Vault.ActionExecuted       ──► actions table              │
  │                                                              │
  │  API endpoints:                                              │
  │    GET /api/pilots            (with ERC-8004 scores)         │
  │    GET /api/pilots/:id                                       │
  │    GET /api/vaults/:address                                  │
  │    GET /api/vaults/:address/actions                          │
  │    GET /api/stats                                            │
  └─────────────────────────────────────────────────────────────┘

  Frontend (Next.js) ──► Indexer API + direct RPC reads
```

---

## 3. Smart Contracts

All contracts are in `contracts/src/`. Compiled and tested with Foundry (`foundry.toml` in `contracts/`).

### 3.1 Vault (`Vault.sol`)

The core contract. One vault per captain, deployed as an ERC-1167 minimal proxy from VaultFactory. The captain retains exclusive withdrawal rights; the pilot may only call `executePlan`.

**Key state:**
- `captain` — the owner address set at initialization.
- `_charters` — mapping from pilot address to `Charter` struct.
- `_pilotDailySpent` / `_pilotDayStart` — rolling 24-hour spend window per pilot.
- `validator` — a `CharterValidator` instance created in `initialize`.
- `reputation` — optional ERC-8004 reputation contract address.

**Functions:**

| Function | Caller | Description |
|---|---|---|
| `initialize(captain, reputation)` | VaultFactory | One-time setup. Creates CharterValidator. |
| `deposit(token, amount)` | Anyone | Pulls ERC-20 into the vault. |
| `withdraw(token, amount, to)` | Captain only | Moves funds out. |
| `hirePilot(charter)` | Captain only | Grants a pilot a bounded mandate. |
| `revokePilot(pilot)` | Captain only | Immediately invalidates charter. |
| `pause()` / `unpause()` | Captain only | Halts all `executePlan` calls. |
| `forceWithdrawAll(to, tokens[])` | Captain only | Emergency full withdrawal. |
| `executePlan(actions[])` | Pilot (charter holder) | Executes a batch of DeFi actions within charter bounds. |
| `getCharter(pilot)` | View | Returns the stored Charter. |
| `getDailySpent(pilot)` | View | Returns current-day cumulative spend. |

**`executePlan` enforcement sequence (in order):**
1. Caller must have a charter (`_hasCharter[msg.sender]`).
2. Charter must not be expired.
3. Reentrancy guard (`_locked`).
4. Vault must not be paused.
5. For each action: `CharterValidator.validate()` must pass.
6. `action.value` must be zero (no ETH transfers).
7. If `tokenIn` is set and `amountIn > 0`, `tokenOut` must also be set (no net outflows without a return token).
8. Balance check: `tokenOut` balance must increase after the call.
9. After all actions: cumulative `amountIn` must not exceed `charter.maxDailyAmountIn`.
10. On success: calls `IERC8004Reputation.postFeedback(pilot, +1, "safe passage")` — wrapped in `try/catch` so a broken reputation contract does not block execution.

### 3.2 VaultFactory (`VaultFactory.sol`)

Deploys Vault proxies using OpenZeppelin's ERC-1167 `Clones` library. One vault per captain (enforced by `vaultOf` mapping).

**Functions:**

| Function | Description |
|---|---|
| `createVault()` | Clones the implementation, initializes it with `msg.sender` as captain, stores in `vaultOf`. Emits `VaultCreated`. |
| `allVaults(start, limit)` | Paginated view of all deployed vaults. |
| `allVaultsCount()` | Total vault count. |

The `reputationRegistry` address is passed into every new vault at construction time so all vaults share the same ERC-8004 contract.

### 3.3 PilotRegistry (`PilotRegistry.sol`)

A public registry where pilot developers list their AI agents. Requires staking USDC as a skin-in-the-game bond.

**Structs:**
- `PilotCard` — human-readable metadata: name, description, risk profile, IPFS metadata URL, supported chains.
- `PilotRecord` — combines card with on-chain state: developer, executor, operator, stake amount, active/slashed flags, registration timestamp.

The **executor** is the on-chain address that will call `executePlan` (the session key). The **operator** is the address used for ERC-8004 reputation lookups and is used by the indexer when fetching scores.

**Functions:**

| Function | Caller | Description |
|---|---|---|
| `registerPilot(card, executor, operator, stake)` | Developer | Stakes USDC, registers pilot, adds to active set. |
| `updatePilotCard(id, card)` | Developer | Updates metadata for an active pilot. |
| `unregisterPilot(id)` | Developer | Deactivates and returns stake (unless slashed). |
| `slashPilot(id, reason)` | Owner | Deactivates pilot and confiscates stake to owner. |
| `setMinStake(newMinStake)` | Owner | Adjusts the minimum stake threshold. |
| `getActivePilotIds(start, limit)` | View | Paginated active pilot IDs. |

### 3.4 ConservativeRWA (`ConservativeRWA.sol`)

A reference `IPilotExecutor` implementation that encapsulates pure on-chain rebalancing logic for the pilot runtime to call as a read-only helper.

**Constants:**
- `DRIFT_THRESHOLD_BPS = 500` — 5% drift from target triggers a rebalance.
- `MAX_SLIPPAGE_BPS = 100` — 1% max slippage (informational, enforced by the balance check in Vault).
- Hardcoded Arbitrum Sepolia addresses for Aave V3 pool, USDC, and aUSDC.

**Functions:**

| Function | Description |
|---|---|
| `computeDrifts(balances[], targetsBps[])` | Returns signed drift in bps for each asset vs target allocation. |
| `shouldRebalance(driftsBps[])` | Returns true if any drift exceeds `DRIFT_THRESHOLD_BPS`. |
| `encodeAaveSupply(asset, amount, onBehalfOf)` | ABI-encodes an Aave `supply` call for the pilot to embed in an `Action`. |
| `encodeAaveWithdraw(asset, amount, to)` | ABI-encodes an Aave `withdraw` call. |
| `validatePlan(actions[], charter)` | Validates all actions against charter targets and `maxSingleAmountIn`. |

### 3.5 CharterValidator (`CharterValidator.sol`)

Stateless validator, instantiated inside each Vault on initialization. Called once per action inside `executePlan`.

Checks per action:
1. `action.target` is in `charter.allowedTargets`.
2. `action.tokenIn` (if set) is in `charter.allowedTokensIn`.
3. `action.tokenOut` (if set) is in `charter.allowedTokensOut`.
4. `action.amountIn` does not exceed `charter.maxSingleAmountIn`.
5. `charter.expiresAt` has not passed.

Also exposes `validatePlan(actions[], charter)` which iterates all actions and returns the first failing index and reason.

### 3.6 MockOracle (`MockOracle.sol`)

A simple price oracle for testnet use. Owner sets USD prices per token. Used by the pilot runtime's `VaultClient` to compute USD values of vault balances.

**Functions:** `setPrice`, `setPrices`, `getPrice`, `getPrices`, `getValue(token, amount, decimals)`.

`getValue` normalizes any token decimal width to 18 decimals before computing USD value.

### 3.7 Interfaces

| File | Purpose |
|---|---|
| `IVault.sol` | Defines `Action`, `VaultState`, `Charter` structs and the `IVault` interface. |
| `IERC8004.sol` | `IERC8004Identity` and `IERC8004Reputation` — the reputation standard interfaces used by Vault and the indexer. |
| `IPilotExecutor.sol` | Interface for on-chain pilot executor contracts: `riskProfile()`, `supportedAssets()`, `validatePlan()`. |

---

## 4. SDK (`@pilotage/pilot-sdk`)

Source: `sdk/src/`. Built to `sdk/dist/`. Published as `@pilotage/pilot-sdk` (local workspace package consumed by `pilot-runtime` and `indexer`).

### Exports

```typescript
// Core loop
export class Pilot                // starts the poll/decide/execute loop
export class VaultClient          // reads vault state from chain

// Types
export type Action, Charter, VaultState, Decision, Strategy, ActionOutcome

export interface PilotConfig {
  vaultAddress: Address;
  pilotPrivateKey: Hex;
  oracleAddress: Address;
  tokens: Address[];
  targetsBps: number[];         // allocation targets in bps, must sum to 10000
  rpcUrl: string;
  pollIntervalMs?: number;      // default 15000ms
  chainId: number;
}

// ABIs (viem-compatible)
export VAULT_ABI
export VAULT_FACTORY_ABI
export PILOT_REGISTRY_ABI
export MOCK_ORACLE_ABI
export ERC20_ABI
export CONSERVATIVE_RWA_ABI
export ERC8004_REPUTATION_ABI
```

### Building a Custom Pilot

A pilot is any object implementing the `Strategy` interface:

```typescript
interface Strategy {
  name: string;
  decide(state: VaultState): Promise<Decision>;
}

type Decision =
  | { type: "hold" }
  | { type: "rebalance"; actions: Action[] };
```

`VaultState` contains token balances, USD values, prices (all as `bigint`), and the pilot's current charter. The strategy must only produce actions that fit within the charter or they will revert on-chain.

Minimal example (`sdk/src/example/simple-rebalancer.ts`):

```typescript
import { encodeFunctionData } from "viem";
import { Pilot } from "@pilotage/pilot-sdk";
import type { Strategy, VaultState, Decision } from "@pilotage/pilot-sdk";

const strategy: Strategy = {
  name: "SimpleRebalancer",
  async decide(state: VaultState): Promise<Decision> {
    const usdcIdx = state.tokens.indexOf(USDC);
    const balance = usdcIdx >= 0 ? state.balances[usdcIdx] : 0n;
    if (balance === 0n) return { type: "hold" };

    return {
      type: "rebalance",
      actions: [{
        target: AAVE_POOL,
        callData: encodeFunctionData({ abi: AAVE_SUPPLY_ABI, functionName: "supply",
          args: [USDC, balance, state.vault, 0] }),
        value: 0n,
        tokenIn: USDC,
        amountIn: balance,
        tokenOut: A_USDC,
      }],
    };
  },
};

new Pilot(strategy, {
  vaultAddress: process.env.VAULT_ADDRESS! as `0x${string}`,
  pilotPrivateKey: process.env.PILOT_PRIVATE_KEY! as `0x${string}`,
  oracleAddress: process.env.ORACLE_ADDRESS! as `0x${string}`,
  tokens: [USDC, A_USDC],
  targetsBps: [0, 10000],
  rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC!,
  chainId: 421614,
}).run();
```

### VaultClient

`VaultClient.readState(tokens, oracleAddress)` issues parallel RPC calls to fetch:
- ERC-20 balances and decimals for each token.
- USD values and raw prices from MockOracle.
- The pilot's current charter from the vault.

Returns a `VaultState` with all values as `bigint` (18-decimal USD, 6-decimal token amounts where applicable).

---

## 5. Pilot Runtime

Source: `pilot-runtime/src/`. TypeScript Node.js process. Runs the ConservativeRWA strategy using `@pilotage/pilot-sdk`.

### Entry Point (`index.ts`)

Instantiates the strategy and the `Pilot` class, wires `SIGINT`/`SIGTERM` for clean shutdown, and calls `pilot.run()`.

### Decision Loop

The `Pilot.run()` method loops at `pollIntervalMs` (default 15 seconds):

```
tick():
  1. VaultClient.isPaused() → skip if paused
  2. VaultClient.readState(tokens, oracle) → VaultState
  3. if totalValueUSD == 0 → skip (no funds)
  4. strategy.decide(state) → Decision
  5. if Decision.type == "hold" → log and skip
  6. walletClient.writeContract(Vault.executePlan(actions))
  7. wait for receipt
  8. log P&L delta
```

### Strategy Logic (`strategy.ts`)

The `ConservativeRWAStrategy.decide()` function:

1. Finds USDC and aUSDC indices in vault state.
2. Calls `ConservativeRWA.computeDrifts(balances, targetsBps)` on-chain (read-only).
3. Calls `ConservativeRWA.shouldRebalance(drifts)` — returns false if all drifts are under 500 bps.
4. If rebalance is needed, determines direction (`supply` idle USDC to Aave, or `withdraw` aUSDC back to idle) and the maximum corrective amount.
5. Calls `decideWithGemini()` with a structured prompt describing current state and proposed move.
6. Gemini returns `{ act: boolean, fraction: number, reason: string }`. If `act` is false, the pilot holds. Otherwise, `fraction` scales the corrective amount (0–1).
7. If Gemini is unavailable (no API key or network error), falls back to rule-based execution at full corrective amount.
8. Returns a single `Action` encoding either `IAaveV3Pool.supply` or `IAaveV3Pool.withdraw`.

### Gemini Integration (`llm.ts`)

- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Model: configurable via `GEMINI_MODEL`, default `gemini-3-flash-preview`.
- Temperature: `0.2` for consistent decision-making.
- Response MIME type forced to `application/json`.
- All errors are caught and return `null`, triggering the rule-based fallback.

### Configuration (`config.ts`)

All configuration is read from environment variables at startup. Required vars throw on missing; optional vars have defaults.

---

## 6. Indexer

Source: `indexer/src/`. Hono HTTP server backed by a PostgreSQL database. Listens on `PORT` (default `3001`).

### Startup Sequence (`index.ts`)

1. `migrate()` — runs schema migrations.
2. `syncHistorical(fromBlock)` — replays all past `VaultCreated` and `PilotRegistered` events from `INDEXER_FROM_BLOCK` (default block 0).
3. `loadKnownVaults()` — loads vault addresses from the DB for the action watcher.
4. Starts three live event watchers: `watchVaultCreated`, `watchPilotRegistered`, `startActionWatcher`.
5. Starts the Hono HTTP server.

### Event Watchers (`events.ts`)

Uses viem's `watchContractEvent` / `getLogs` with ABIs from `@pilotage/pilot-sdk`.

| Event | Source | DB Target | Notes |
|---|---|---|---|
| `VaultCreated` | VaultFactory | `vaults` | Triggers restart of `ActionExecuted` watcher with new vault added. |
| `PilotRegistered` | PilotRegistry | `pilots` | Reads full `PilotRecord` from chain via `getPilot(id)`. Upserts on re-registration. |
| `ActionExecuted` | Each Vault | `actions` | Stores pilot, token in/out, amount, success flag, block number, tx hash. Deduplicates on `tx_hash`. |

### API Endpoints (`api.ts`)

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/pilots` | List active, non-slashed pilots. Query params: `risk` (filter by risk profile), `limit` (max 100), `offset`. Sorted by ERC-8004 score descending. |
| `GET` | `/api/pilots/:id` | Single pilot by registry ID. Includes `pilotage_score`. |
| `GET` | `/api/vaults/:address` | Vault metadata. |
| `GET` | `/api/vaults/:address/actions` | Recent actions for a vault. Query param: `limit` (max 200). |
| `GET` | `/api/stats` | Aggregate counts: total vaults, active pilots, successful actions. |

All routes have CORS headers enabled (`cors()` middleware).

### Reputation Reading (`reputation.ts`)

`readScores(operators[])` batch-reads `getScore(operator)` from the ERC-8004 reputation contract for a list of operator addresses. Returns `null` for each address if `ERC8004_REPUTATION` or `ARBITRUM_SEPOLIA_RPC` is not configured, or if the individual `readContract` call fails.

---

## 7. Key Flows

### 7.1 Captain Creates Vault and Deposits

1. Captain calls `VaultFactory.createVault()`.
   - Factory clones the Vault implementation via ERC-1167.
   - Calls `Vault.initialize(captain, reputationRegistry)`.
   - Stores vault in `vaultOf[captain]`, emits `VaultCreated`.
2. Indexer detects `VaultCreated`, inserts into `vaults` table, restarts action watcher with new vault included.
3. Captain approves ERC-20 (e.g., USDC) on the token contract for the vault address.
4. Captain calls `Vault.deposit(usdc, amount)`.
   - Vault calls `IERC20(usdc).transferFrom(captain, vault, amount)`.
   - Emits `Deposited`.

### 7.2 Pilot Gets Registered and Hired

**Registration (developer):**
1. Developer approves `PilotRegistry` to spend `stake` USDC.
2. Developer calls `PilotRegistry.registerPilot(card, executorAddress, operatorAddress, stake)`.
   - Registry pulls USDC from developer.
   - Creates `PilotRecord`, assigns sequential ID, adds to active set.
   - Emits `PilotRegistered`.
3. Indexer picks up event, fetches full record, inserts into `pilots` table.

**Hiring (captain):**
1. Captain constructs a `Charter`:
   ```
   Charter {
     pilot: <executor address>,
     allowedTargets: [aavePoolAddress],
     allowedTokensIn: [usdcAddress, aUsdcAddress],
     allowedTokensOut: [usdcAddress, aUsdcAddress],
     maxSingleAmountIn: <e.g. 1000e6>,
     maxDailyAmountIn: <e.g. 5000e6>,
     expiresAt: <unix timestamp or 0 for no expiry>
   }
   ```
2. Captain calls `Vault.hirePilot(charter)`.
   - Stores charter in `_charters[pilot]`, sets `_hasCharter[pilot] = true`.
   - Emits `PilotHired`.

### 7.3 Pilot Executes a Rebalance

1. Pilot runtime polls: `VaultClient.readState()` reads balances, oracle prices, and charter from chain.
2. Strategy calls `ConservativeRWA.computeDrifts()` on-chain — computes signed deviation from target allocation.
3. Strategy calls `ConservativeRWA.shouldRebalance()` — true if max drift >= 500 bps.
4. `decideWithGemini()` is called with a structured context prompt. Gemini responds with `{ act: true, fraction: 0.85, reason: "..." }`.
5. Strategy scales the corrective amount by `fraction`, builds an `Action` struct encoding the Aave call.
6. `Pilot.submitPlan([action])` calls `walletClient.writeContract(Vault.executePlan([action]))`.
7. On-chain in `executePlan`:
   a. Charter and expiry checks pass.
   b. Daily spend window resets if 24 hours have elapsed.
   c. `CharterValidator.validate(action, charter)` — target and token whitelists checked, amountIn checked.
   d. `IERC20(tokenIn).approve(aavePool, amountIn)`.
   e. `aavePool.call(encodeAaveSupply(...))` or `aavePool.call(encodeAaveWithdraw(...))`.
   f. Approval reset to zero.
   g. Balance check: `aUSDC` (or `USDC`) balance must be higher after the call.
   h. Cumulative daily spend updated.
   i. `IERC8004Reputation.postFeedback(pilot, +1, "safe passage")` — score increments on-chain.
   j. Emits `ActionExecuted`.
8. Indexer detects `ActionExecuted`, inserts into `actions` table.
9. Pilot runtime reads updated vault value, logs P&L delta.

---

## 8. Security Model

Pilotage uses a two-layer defense so that a fully compromised pilot process can cause zero loss beyond charter-bounded amounts.

### Layer 1: CharterValidator (Whitelist)

Before any external call is made, `CharterValidator.validate()` checks:
- **Target whitelist** — the pilot can only call contracts the captain explicitly approved (e.g., only the Aave V3 pool address).
- **Token whitelist** — `tokenIn` and `tokenOut` must both be on the captain's approved list.
- **Per-action spend cap** — `amountIn` must not exceed `maxSingleAmountIn`.
- **Charter expiry** — calls fail after `expiresAt`.

A pilot that attempts to call any other contract (e.g., an attacker-controlled contract, a DEX not on the list) will revert at this layer before any state changes.

### Layer 2: Balance Check (No-Drain Guarantee)

After each external call, Vault verifies:
- `tokenOut` balance of the vault is strictly greater than before the call.
- ETH value in any action must be zero.
- If `tokenIn` and `amountIn > 0` are set, `tokenOut` must also be set — the pilot cannot make a net outflow call that produces no return.

This means that even if a whitelisted contract has a bug or is upgraded maliciously, the vault will revert any call that does not return tokens.

**Daily spend cap** further limits total exposure within any 24-hour rolling window.

### What a Malicious Pilot Can Do

- Execute any combination of allowed operations up to `maxDailyAmountIn` per day.
- Temporarily shift allocation between charter-whitelisted tokens.
- Generate spurious `postFeedback` calls if the pilot constructs empty action arrays (the reputation call requires `actions.length > 0`).

### What a Malicious Pilot Cannot Do

- Send funds to any address not on the target whitelist.
- Use tokens not on the token whitelist.
- Spend more than `maxSingleAmountIn` per action or `maxDailyAmountIn` per day.
- Call contracts with ETH value.
- Make calls that result in a net token outflow from the vault.
- Act after charter expiry.
- Bypass the captain's `pause()` or `revokePilot()`.

The captain retains unconditional `withdraw` and `forceWithdrawAll` access regardless of pilot state.

---

## 9. ERC-8004 Reputation

ERC-8004 is a proposed standard for on-chain agent reputation (identity + feedback scores). Pilotage uses the `IERC8004Reputation` interface:

```solidity
interface IERC8004Reputation {
    function postFeedback(address subject, int256 score, string calldata metadata) external;
    function getScore(address subject) external view returns (int256 score);
    function getFeedbackCount(address subject) external view returns (uint256);
}
```

### Score Accumulation

Every time a pilot successfully executes a non-empty plan in `executePlan`, the vault calls:

```solidity
IERC8004Reputation(reputation).postFeedback(msg.sender, int256(1), "safe passage")
```

The call is wrapped in `try/catch` so a broken reputation contract does not block execution. Scores are signed integers — future implementations may post negative scores for bad behavior via the `slashPilot` path or governance.

The `msg.sender` passed to `postFeedback` is the **executor address** (the session key that signed `executePlan`). The indexer maps this to the **operator address** stored in `PilotRegistry` when reading scores for API responses. In the current reference implementation, the developer is the operator; in production these may differ.

### Indexer Score Integration

`indexer/src/reputation.ts` exports `readScores(operators[])` which batch-calls `getScore` for a list of operator addresses. The `/api/pilots` endpoint appends `pilotage_score` to each pilot record and sorts results by score descending, so the most reputable pilots surface first in the marketplace.

If `ERC8004_REPUTATION` is not set in the environment, `readScores` returns `null` for all addresses and the sort still works (nulls sort below any number).

---

## 10. Environment Variables

All variables are read by the services listed. Copy `.env.example` to `.env` and fill in values.

| Variable | Required by | Description |
|---|---|---|
| `PRIVATE_KEY` | Deploy scripts | Deployer private key (testnet only). |
| `DEPLOYER_ADDRESS` | Deploy scripts | Public address matching `PRIVATE_KEY`. |
| `ARBITRUM_SEPOLIA_RPC` | All services | RPC endpoint for Arbitrum Sepolia (chain ID 421614). |
| `ARBISCAN_API_KEY` | Deploy scripts | Arbiscan key for contract verification with `--verify`. |
| `GEMINI_API_KEY` | Pilot runtime | Google Gemini API key. If empty, runtime uses rule-based fallback. |
| `GEMINI_MODEL` | Pilot runtime | Gemini model ID. Default: `gemini-3-flash-preview`. |
| `ERC8004_REPUTATION` | Vault (deploy), indexer | Deployed ERC-8004 reputation contract address. Optional; reputation is skipped if empty. |
| `VAULT_FACTORY` | Indexer, frontend | Deployed VaultFactory address (from `Deploy.s.sol` output). |
| `PILOT_REGISTRY` | Indexer, frontend | Deployed PilotRegistry address. |
| `CONSERVATIVE_RWA` | Pilot runtime, frontend | Deployed ConservativeRWA address. |
| `ORACLE_ADDRESS` | Pilot runtime, frontend | Deployed MockOracle address. |
| `VAULT_ADDRESS` | Pilot runtime | Specific vault the runtime will manage (from `setup-vault.sh` output). |
| `USDC_ADDRESS` | Pilot runtime | USDC token address. Default: `0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d` (Arb Sepolia). |
| `AAVE_POOL` | Pilot runtime | Aave V3 pool address. Default: `0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff`. |
| `A_USDC_ADDRESS` | Pilot runtime | aUSDC token address. Default: `0x460b97BD498E1157530AEb3086301d5225b91216`. |
| `PILOT_PRIVATE_KEY` | Pilot runtime | Private key of the pilot's session wallet (the executor address hired in the charter). |
| `POLL_INTERVAL_MS` | Pilot runtime | How often the pilot polls for drift. Default: `15000` (15 seconds). |
| `TARGET_USDC_BPS` | Pilot runtime | Target idle USDC allocation in basis points. Default: `5000` (50%). |
| `TARGET_AUSDC_BPS` | Pilot runtime | Target aUSDC allocation in basis points. Default: `5000` (50%). Must sum to 10000. |
| `DATABASE_URL` | Indexer | PostgreSQL connection string. Default: `postgresql://pilotage:pilotage@localhost:5432/pilotage`. |
| `PORT` | Indexer | HTTP port for the indexer API. Default: `3001`. |
| `INDEXER_FROM_BLOCK` | Indexer | Block number to start historical sync from. Default: `0`. Set to deployment block for faster startup. |
| `CHAIN_ID` | Indexer, pilot runtime | Chain ID. Default: `421614` (Arbitrum Sepolia). |
| `NEXT_PUBLIC_VAULT_FACTORY` | Frontend | VaultFactory address for client-side use. |
| `NEXT_PUBLIC_PILOT_REGISTRY` | Frontend | PilotRegistry address for client-side use. |
| `NEXT_PUBLIC_CONSERVATIVE_RWA` | Frontend | ConservativeRWA address for client-side use. |
| `NEXT_PUBLIC_ORACLE` | Frontend | Oracle address for client-side use. |
| `NEXT_PUBLIC_USDC` | Frontend | USDC token address for client-side use. |
| `NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC` | Frontend | RPC URL for client-side viem. |
| `NEXT_PUBLIC_CHAIN_ID` | Frontend | Chain ID for client-side use. Default: `421614`. |

---

## 11. Development Commands

### Prerequisites

- [Foundry](https://getfoundry.sh/) (`forge`, `cast`)
- Node.js >= 20
- PostgreSQL (or Docker — `docker-compose.yml` provided)
- A funded Arbitrum Sepolia wallet

### Install Dependencies

```bash
# Install and build all TypeScript packages
npm run setup

# Or individually:
npm install --prefix sdk && npm run build --prefix sdk
npm install --prefix pilot-runtime
npm install --prefix indexer
```

### Smart Contracts

```bash
# Run all contract tests (verbose)
npm run test:contracts
# Equivalent to:
forge test --root contracts -vv

# Run a specific test file
forge test --root contracts --match-path "test/Vault.t.sol" -vvv

# Deploy to Arbitrum Sepolia
forge script contracts/script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv

# Deploy oracle separately (after Deploy.s.sol)
forge script contracts/script/DeployOracle.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  -vvvv
```

### Vault Setup (after deploying contracts)

```bash
# Creates a vault, deposits USDC, hires the ConservativeRWA pilot
bash scripts/setup-vault.sh
```

### Start Services

```bash
# Start PostgreSQL via Docker Compose
docker compose up -d

# Start the indexer (watches chain events, serves API)
npm run dev:indexer

# Start the pilot runtime (polls vault, calls Gemini, executes rebalances)
npm run dev:runtime
```

### Demo Utilities

```bash
# Reset the demo vault to a known state
npm run demo:reset
# Equivalent to: bash scripts/reset-demo.sh

# Trigger a simulated price drop to induce drift and observe rebalance
npm run demo:drop
# Equivalent to: bash scripts/trigger-price-drop.sh
```

### Contract Test Files

| File | Coverage |
|---|---|
| `contracts/test/Vault.t.sol` | executePlan guards, charter enforcement, daily limits, reentrancy |
| `contracts/test/VaultFactory.t.sol` | Proxy deployment, one-vault-per-captain constraint |
| `contracts/test/PilotRegistry.t.sol` | Staking, slash, unregister, access control |
| `contracts/test/ConservativeRWA.t.sol` | Drift computation, rebalance threshold, calldata encoding |
| `contracts/test/CharterValidator.t.sol` | Whitelist checks, expiry checks |
