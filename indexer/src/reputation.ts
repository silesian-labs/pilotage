import {
  createPublicClient,
  http,
  type Address,
  type PublicClient,
} from "viem";
import { ERC8004_REPUTATION_ABI } from "@pilotage/pilot-sdk";

const RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC ?? "";
const REPUTATION = (process.env.ERC8004_REPUTATION ?? "") as Address;

const client: PublicClient | null = RPC_URL
  ? createPublicClient({ transport: http(RPC_URL) })
  : null;

export const reputationEnabled = Boolean(client && REPUTATION);

export async function readScores(
  operators: Address[],
): Promise<(number | null)[]> {
  if (!reputationEnabled || !client) return operators.map(() => null);

  return Promise.all(
    operators.map(async (operator) => {
      try {
        const score = await client.readContract({
          address: REPUTATION,
          abi: ERC8004_REPUTATION_ABI,
          functionName: "getScore",
          args: [operator],
        });
        return Number(score);
      } catch {
        return null;
      }
    }),
  );
}
