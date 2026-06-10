import {
  createPublicClient,
  http,
  type Address,
  type PublicClient,
} from "viem";
import { ERC20_ABI, VAULT_ABI, MOCK_ORACLE_ABI } from "./abis.js";
import type { VaultState, Charter } from "./types.js";

export class VaultClient {
  private client: PublicClient;

  constructor(
    private vaultAddress: Address,
    private pilotAddress: Address,
    rpcUrl: string,
  ) {
    this.client = createPublicClient({ transport: http(rpcUrl) });
  }

  async readState(
    tokens: Address[],
    oracleAddress: Address,
  ): Promise<VaultState> {
    const [balances, decimals] = await Promise.all([
      Promise.all(
        tokens.map((token) =>
          this.client.readContract({
            address: token,
            abi: ERC20_ABI,
            functionName: "balanceOf",
            args: [this.vaultAddress],
          }),
        ),
      ),
      Promise.all(
        tokens.map((token) =>
          this.client.readContract({
            address: token,
            abi: ERC20_ABI,
            functionName: "decimals",
          }),
        ),
      ),
    ]);

    const [valuesUSD, prices, charter] = await Promise.all([
      Promise.all(
        tokens.map((token, i) =>
          this.client.readContract({
            address: oracleAddress,
            abi: MOCK_ORACLE_ABI,
            functionName: "getValue",
            args: [token, balances[i], decimals[i]],
          }),
        ),
      ),
      Promise.all(
        tokens.map((token) =>
          this.client.readContract({
            address: oracleAddress,
            abi: MOCK_ORACLE_ABI,
            functionName: "getPrice",
            args: [token],
          }),
        ),
      ),
      this.client.readContract({
        address: this.vaultAddress,
        abi: VAULT_ABI,
        functionName: "getCharter",
        args: [this.pilotAddress],
      }),
    ]);

    return {
      vault: this.vaultAddress,
      tokens,
      balances,
      prices,
      valuesUSD,
      totalValueUSD: valuesUSD.reduce((sum, v) => sum + v, 0n),
      charter: charter as Charter,
    };
  }

  async isPaused(): Promise<boolean> {
    return this.client.readContract({
      address: this.vaultAddress,
      abi: VAULT_ABI,
      functionName: "isPaused",
    });
  }
}
