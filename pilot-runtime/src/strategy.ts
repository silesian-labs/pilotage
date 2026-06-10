import { createPublicClient, http, type Address } from "viem";
import { CONSERVATIVE_RWA_ABI } from "@pilotage/pilot-sdk";
import type {
  Strategy,
  VaultState,
  Decision,
  Action,
} from "@pilotage/pilot-sdk";
import { encodeAaveSupply, encodeAaveWithdraw } from "./aave.js";
import { decideWithGemini } from "./llm.js";
import { config } from "./config.js";

export function makeConservativeRWAStrategy(
  executorAddress: Address,
  aavePool: Address,
  usdc: Address,
  aUsdc: Address,
): Strategy {
  const client = createPublicClient({ transport: http(config.rpcUrl) });

  return {
    name: "ConservativeRWA",

    async decide(state: VaultState): Promise<Decision> {
      const usdcIdx = state.tokens.indexOf(usdc);
      const aUsdcIdx = state.tokens.indexOf(aUsdc);

      if (usdcIdx === -1 || aUsdcIdx === -1) {
        console.warn("[strategy] token not found in vault state");
        return { type: "hold" };
      }

      const usdcVal = state.valuesUSD[usdcIdx];
      const aUsdcVal = state.valuesUSD[aUsdcIdx];
      const total = state.totalValueUSD;

      console.log(
        `[strategy] USDC: $${fmt18(usdcVal)} | aUSDC: $${fmt18(aUsdcVal)} | total: $${fmt18(total)}`,
      );

      if (total === 0n) return { type: "hold" };

      const drifts = await client.readContract({
        address: executorAddress,
        abi: CONSERVATIVE_RWA_ABI,
        functionName: "computeDrifts",
        args: [[usdcVal, aUsdcVal], config.targetsBps.map(BigInt)],
      });

      const shouldRebalance = await client.readContract({
        address: executorAddress,
        abi: CONSERVATIVE_RWA_ABI,
        functionName: "shouldRebalance",
        args: [drifts],
      });

      if (!shouldRebalance) {
        console.log("[strategy] drift within threshold — holding");
        return { type: "hold" };
      }

      const maxDriftBps = Number(
        drifts.reduce((m, d) => (abs(d) > m ? abs(d) : m), 0n),
      );
      console.log(
        `[strategy] drift ${drifts.map((d) => `${d}bps`).join(", ")} — consulting pilot`,
      );

      const targetUsdcVal =
        (total * BigInt(config.targetsBps[usdcIdx])) / 10_000n;
      const priceUsdc = state.prices[usdcIdx];

      let direction: "supply" | "withdraw";
      let maxAmount: bigint;

      if (usdcVal > targetUsdcVal) {
        direction = "supply";
        maxAmount = min(
          usdToToken(usdcVal - targetUsdcVal, priceUsdc, 6),
          state.balances[usdcIdx],
        );
      } else {
        direction = "withdraw";
        maxAmount = min(
          usdToToken(targetUsdcVal - usdcVal, priceUsdc, 6),
          state.balances[aUsdcIdx],
        );
      }

      if (maxAmount === 0n) return { type: "hold" };

      const llm = await decideWithGemini({
        usdcValueUsd: Number(usdcVal) / 1e18,
        aUsdcValueUsd: Number(aUsdcVal) / 1e18,
        totalUsd: Number(total) / 1e18,
        targetUsdcPct: config.targetsBps[usdcIdx] / 100,
        driftBps: maxDriftBps,
        direction,
        maxAmountUsdc: Number(maxAmount) / 1e6,
      });

      if (llm) {
        console.log(
          `[pilot:gemini] act=${llm.act} fraction=${llm.fraction.toFixed(2)} — "${llm.reason}"`,
        );
        if (!llm.act) return { type: "hold" };
      } else {
        console.log(
          "[pilot:rule-based] LLM unavailable — full corrective move",
        );
      }

      const fractionPermille = llm
        ? BigInt(Math.round(llm.fraction * 1000))
        : 1000n;
      const amount = (maxAmount * fractionPermille) / 1000n;
      if (amount === 0n) return { type: "hold" };

      const action: Action =
        direction === "supply"
          ? {
              target: aavePool,
              callData: encodeAaveSupply(usdc, amount, state.vault),
              value: 0n,
              tokenIn: usdc,
              amountIn: amount,
              tokenOut: aUsdc,
            }
          : {
              target: aavePool,
              callData: encodeAaveWithdraw(usdc, amount, state.vault),
              value: 0n,
              tokenIn: aUsdc,
              amountIn: amount,
              tokenOut: usdc,
            };

      console.log(
        `  → ${direction} ${fmt6(amount)} USDC ${direction === "supply" ? "to" : "from"} Aave`,
      );
      return { type: "rebalance", actions: [action] };
    },
  };
}

function abs(v: bigint): bigint {
  return v < 0n ? -v : v;
}

function usdToToken(valueUsd: bigint, price: bigint, decimals: number): bigint {
  if (price === 0n) return 0n;
  return (valueUsd * 10n ** BigInt(decimals)) / price;
}

function min(a: bigint, b: bigint): bigint {
  return a < b ? a : b;
}

function fmt6(v: bigint): string {
  return (Number(v) / 1e6).toFixed(2);
}

function fmt18(v: bigint): string {
  return (Number(v) / 1e18).toFixed(2);
}
