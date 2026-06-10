import type { Address, Hex } from "viem";

function required(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

function optional(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

export const config = {
  rpcUrl: required("ARBITRUM_SEPOLIA_RPC"),
  pilotPrivateKey: required("PILOT_PRIVATE_KEY") as Hex,
  vaultAddress: required("VAULT_ADDRESS") as Address,
  oracleAddress: required("ORACLE_ADDRESS") as Address,
  executorAddress: required("CONSERVATIVE_RWA") as Address,

  usdc: optional(
    "USDC_ADDRESS",
    "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
  ) as Address,
  aUsdc: optional(
    "A_USDC_ADDRESS",
    "0x460b97BD498E1157530AEb3086301d5225b91216",
  ) as Address,
  aavePool: optional(
    "AAVE_POOL",
    "0xBfC91D59fdAA134A4ED45f7B584cAf96D7792Eff",
  ) as Address,

  pollIntervalMs: Number(optional("POLL_INTERVAL_MS", "15000")),
  chainId: Number(optional("CHAIN_ID", "421614")),

  geminiApiKey: optional("GEMINI_API_KEY", ""),
  geminiModel: optional("GEMINI_MODEL", "gemini-3-flash-preview"),

  targetsBps: [
    Number(optional("TARGET_USDC_BPS", "5000")),
    Number(optional("TARGET_AUSDC_BPS", "5000")),
  ] as number[],
} as const;
