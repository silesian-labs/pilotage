import { encodeFunctionData } from "viem";
import { Pilot } from "../pilot.js";
import type { Strategy, VaultState, Decision } from "../types.js";

const USDC = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d" as const;
const A_USDC = "0x460b97BD498E1157530AEb3086301d5225b91216" as const;
const AAVE_POOL = "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff" as const;

const AAVE_SUPPLY_ABI = [
  {
    name: "supply",
    type: "function" as const,
    inputs: [
      { name: "asset", type: "address" },
      { name: "amount", type: "uint256" },
      { name: "onBehalfOf", type: "address" },
      { name: "referralCode", type: "uint16" },
    ],
    outputs: [],
    stateMutability: "nonpayable" as const,
  },
];

const strategy: Strategy = {
  name: "SimpleRebalancer",

  async decide(state: VaultState): Promise<Decision> {
    const usdcIdx = state.tokens.indexOf(USDC);
    const usdcBalance = usdcIdx >= 0 ? state.balances[usdcIdx] : 0n;

    if (usdcBalance === 0n) return { type: "hold" };

    const callData = encodeFunctionData({
      abi: AAVE_SUPPLY_ABI,
      functionName: "supply",
      args: [USDC, usdcBalance, state.vault, 0],
    });

    return {
      type: "rebalance",
      actions: [
        {
          target: AAVE_POOL,
          callData,
          value: 0n,
          tokenIn: USDC,
          amountIn: usdcBalance,
          tokenOut: A_USDC,
        },
      ],
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
