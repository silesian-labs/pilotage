import type { Address, Hex } from "viem";

export interface Action {
  target: Address;
  callData: Hex;
  value: bigint;
  tokenIn: Address;
  amountIn: bigint;
  tokenOut: Address;
}

export interface Charter {
  pilot: Address;
  allowedTargets: Address[];
  allowedTokensIn: Address[];
  allowedTokensOut: Address[];
  maxSingleAmountIn: bigint;
  maxDailyAmountIn: bigint;
  expiresAt: bigint;
}

export interface VaultState {
  vault: Address;
  tokens: Address[];
  balances: bigint[];
  prices: bigint[];
  valuesUSD: bigint[];
  totalValueUSD: bigint;
  charter: Charter;
}

export type Decision =
  | { type: "hold" }
  | { type: "rebalance"; actions: Action[] };

export interface Strategy {
  name: string;
  decide(state: VaultState): Promise<Decision>;
}

export interface ActionOutcome {
  txHash: Hex;
  success: boolean;
  actions: Action[];
  pnlDeltaUSD: bigint;
  timestamp: number;
}
