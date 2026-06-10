import {
  createWalletClient,
  createPublicClient,
  http,
  type WalletClient,
  type PublicClient,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { VAULT_ABI } from "./abis.js";
import type { Action, Strategy, ActionOutcome } from "./types.js";
import { VaultClient } from "./vault-client.js";

export interface PilotConfig {
  vaultAddress: Address;
  pilotPrivateKey: Hex;
  oracleAddress: Address;
  tokens: Address[];
  targetsBps: number[];
  rpcUrl: string;
  pollIntervalMs?: number;
  chainId: number;
}

export class Pilot {
  private walletClient: WalletClient;
  private publicClient: PublicClient;
  private vaultClient: VaultClient;
  private account: ReturnType<typeof privateKeyToAccount>;
  private running = false;

  constructor(
    private strategy: Strategy,
    private config: PilotConfig,
  ) {
    this.account = privateKeyToAccount(config.pilotPrivateKey);
    this.walletClient = createWalletClient({
      account: this.account,
      transport: http(config.rpcUrl),
    });
    this.publicClient = createPublicClient({
      transport: http(config.rpcUrl),
    });
    this.vaultClient = new VaultClient(
      config.vaultAddress,
      this.account.address,
      config.rpcUrl,
    );
  }

  async run(): Promise<void> {
    this.running = true;
    const interval = this.config.pollIntervalMs ?? 15_000;

    console.log(`[${this.strategy.name}] Starting pilot`);
    console.log(`  vault:  ${this.config.vaultAddress}`);
    console.log(`  pilot:  ${this.account.address}`);
    console.log(`  poll:   ${interval}ms`);

    while (this.running) {
      try {
        await this.tick();
      } catch (err) {
        console.error(`[${this.strategy.name}] tick error:`, err);
      }
      await sleep(interval);
    }
  }

  stop(): void {
    this.running = false;
  }

  private async tick(): Promise<void> {
    if (await this.vaultClient.isPaused()) {
      console.log(`[${this.strategy.name}] vault is paused — skipping`);
      return;
    }

    const state = await this.vaultClient.readState(
      this.config.tokens,
      this.config.oracleAddress,
    );

    if (state.totalValueUSD === 0n) {
      console.log(`[${this.strategy.name}] vault empty — waiting for deposit`);
      return;
    }

    const decision = await this.strategy.decide(state);

    if (decision.type === "hold") {
      console.log(`[${this.strategy.name}] holding — no rebalance needed`);
      return;
    }

    console.log(
      `[${this.strategy.name}] rebalancing — ${decision.actions.length} action(s)`,
    );

    const valueBefore = state.totalValueUSD;
    const outcome = await this.submitPlan(decision.actions);

    if (outcome.success) {
      const valueAfter = await this.readTotalValue();
      const pnl = valueAfter - valueBefore;
      console.log(
        `[${this.strategy.name}] tx ${outcome.txHash} — P&L: $${formatUSD(pnl)}`,
      );
    } else {
      console.error(`[${this.strategy.name}] plan failed`);
    }
  }

  private async submitPlan(actions: Action[]): Promise<ActionOutcome> {
    try {
      const hash = await this.walletClient.writeContract({
        address: this.config.vaultAddress,
        abi: VAULT_ABI,
        functionName: "executePlan",
        args: [actions],
        chain: null,
        account: this.account,
      });

      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash,
      });

      return {
        txHash: hash,
        success: receipt.status === "success",
        actions,
        pnlDeltaUSD: 0n,
        timestamp: Date.now(),
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error(`[${this.strategy.name}] submit error:`, msg);
      return {
        txHash: "0x",
        success: false,
        actions,
        pnlDeltaUSD: 0n,
        timestamp: Date.now(),
      };
    }
  }

  private async readTotalValue(): Promise<bigint> {
    const state = await this.vaultClient.readState(
      this.config.tokens,
      this.config.oracleAddress,
    );
    return state.totalValueUSD;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function formatUSD(v: bigint): string {
  const abs = v < 0n ? -v : v;
  const dollars = abs / 10n ** 18n;
  const sign = v < 0n ? "-" : "+";
  return `${sign}$${dollars}`;
}
