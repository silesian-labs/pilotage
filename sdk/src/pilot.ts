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
import { VAULT_ABI, VAULT_FACTORY_ABI } from "./abis.js";
import type { Action, Strategy, ActionOutcome, Charter } from "./types.js";
import { VaultClient } from "./vault-client.js";

export interface PilotConfig {
  /** Manage exactly this one vault. If omitted, the pilot auto-discovers every
   *  vault that has hired it (requires `vaultFactory`). */
  vaultAddress?: Address;
  /** VaultFactory address — enables auto-discovery when `vaultAddress` is unset. */
  vaultFactory?: Address;
  /** How often to re-scan the factory for newly hired/revoked vaults. */
  discoveryIntervalMs?: number;
  pilotPrivateKey: Hex;
  oracleAddress: Address;
  tokens: Address[];
  targetsBps: number[];
  rpcUrl: string;
  pollIntervalMs?: number;
  chainId: number;
}

const ZERO = "0x0000000000000000000000000000000000000000";

export class Pilot {
  private walletClient: WalletClient;
  private publicClient: PublicClient;
  private account: ReturnType<typeof privateKeyToAccount>;
  private running = false;

  private vaultClients = new Map<string, VaultClient>();
  private managedVaults: Address[] = [];
  private lastDiscovery = 0;

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
  }

  async run(): Promise<void> {
    this.running = true;
    const interval = this.config.pollIntervalMs ?? 15_000;

    console.log(`[${this.strategy.name}] Starting pilot`);
    console.log(`  pilot:  ${this.account.address}`);
    if (this.config.vaultAddress) {
      console.log(`  mode:   single vault (${this.config.vaultAddress})`);
    } else if (this.config.vaultFactory) {
      console.log(`  mode:   auto-discover via factory ${this.config.vaultFactory}`);
    } else {
      console.warn("  mode:   no vaultAddress and no vaultFactory — nothing to manage");
    }
    console.log(`  poll:   ${interval}ms`);

    while (this.running) {
      try {
        await this.refreshManagedVaults();

        if (this.managedVaults.length === 0) {
          console.log(`[${this.strategy.name}] no vaults to manage right now`);
        }

        for (const vault of this.managedVaults) {
          try {
            await this.tick(vault);
          } catch (err) {
            console.error(`[${this.strategy.name}] tick error (vault ${vault}):`, err);
          }
        }
      } catch (err) {
        console.error(`[${this.strategy.name}] loop error:`, err);
      }
      await sleep(interval);
    }
  }

  stop(): void {
    this.running = false;
  }

  /** Refresh the set of vaults this pilot is responsible for. */
  private async refreshManagedVaults(): Promise<void> {
    // Single-vault override: pin to exactly one vault.
    if (this.config.vaultAddress) {
      if (this.managedVaults.length === 0) {
        this.managedVaults = [this.config.vaultAddress];
      }
      return;
    }
    if (!this.config.vaultFactory) {
      this.managedVaults = [];
      return;
    }

    const discoveryInterval = this.config.discoveryIntervalMs ?? 60_000;
    const stale = Date.now() - this.lastDiscovery >= discoveryInterval;
    if (!stale && this.managedVaults.length > 0) return;

    this.lastDiscovery = Date.now();
    const found = await this.discoverVaults();

    const prev = new Set(this.managedVaults.map((v) => v.toLowerCase()));
    const next = new Set(found.map((v) => v.toLowerCase()));
    for (const v of found) {
      if (!prev.has(v.toLowerCase())) {
        console.log(`[${this.strategy.name}] now managing vault ${v}`);
      }
    }
    for (const v of this.managedVaults) {
      if (!next.has(v.toLowerCase())) {
        console.log(`[${this.strategy.name}] stopped managing vault ${v}`);
        this.vaultClients.delete(v.toLowerCase());
      }
    }
    this.managedVaults = found;
  }

  /** Scan the factory for every vault whose active charter names this pilot. */
  private async discoverVaults(): Promise<Address[]> {
    const factory = this.config.vaultFactory!;
    const count = (await this.publicClient.readContract({
      address: factory,
      abi: VAULT_FACTORY_ABI,
      functionName: "allVaultsCount",
    })) as bigint;

    if (count === 0n) return [];

    const all = (await this.publicClient.readContract({
      address: factory,
      abi: VAULT_FACTORY_ABI,
      functionName: "allVaults",
      args: [0n, count],
    })) as Address[];

    const me = this.account.address.toLowerCase();
    const now = BigInt(Math.floor(Date.now() / 1000));
    const mine: Address[] = [];

    for (const vault of all) {
      try {
        const charter = (await this.publicClient.readContract({
          address: vault,
          abi: VAULT_ABI,
          functionName: "getCharter",
          args: [this.account.address],
        })) as Charter;

        const isMine = charter.pilot.toLowerCase() === me && charter.pilot !== ZERO;
        const notExpired = charter.expiresAt === 0n || charter.expiresAt > now;
        if (isMine && notExpired) mine.push(vault);
      } catch {
        // unreadable vault — skip
      }
    }
    return mine;
  }

  private vaultClientFor(vault: Address): VaultClient {
    const key = vault.toLowerCase();
    let client = this.vaultClients.get(key);
    if (!client) {
      client = new VaultClient(vault, this.account.address, this.config.rpcUrl);
      this.vaultClients.set(key, client);
    }
    return client;
  }

  private async tick(vault: Address): Promise<void> {
    const vaultClient = this.vaultClientFor(vault);

    if (await vaultClient.isPaused()) {
      console.log(`[${this.strategy.name}] vault ${vault} paused — skipping`);
      return;
    }

    const state = await vaultClient.readState(
      this.config.tokens,
      this.config.oracleAddress,
    );

    if (state.totalValueUSD === 0n) {
      console.log(`[${this.strategy.name}] vault ${vault} empty — waiting for deposit`);
      return;
    }

    const decision = await this.strategy.decide(state);

    if (decision.type === "hold") {
      console.log(`[${this.strategy.name}] vault ${vault} — holding`);
      return;
    }

    console.log(
      `[${this.strategy.name}] vault ${vault} — rebalancing (${decision.actions.length} action(s))`,
    );

    const valueBefore = state.totalValueUSD;
    const outcome = await this.submitPlan(vault, decision.actions);

    if (outcome.success) {
      const valueAfter = (await vaultClient.readState(
        this.config.tokens,
        this.config.oracleAddress,
      )).totalValueUSD;
      const pnl = valueAfter - valueBefore;
      console.log(
        `[${this.strategy.name}] vault ${vault} — tx ${outcome.txHash} · P&L: $${formatUSD(pnl)}`,
      );
    } else {
      console.error(`[${this.strategy.name}] vault ${vault} — plan failed`);
    }
  }

  private async submitPlan(
    vault: Address,
    actions: Action[],
  ): Promise<ActionOutcome> {
    try {
      const hash = await this.walletClient.writeContract({
        address: vault,
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
      console.error(`[${this.strategy.name}] submit error (vault ${vault}):`, msg);
      return {
        txHash: "0x",
        success: false,
        actions,
        pnlDeltaUSD: 0n,
        timestamp: Date.now(),
      };
    }
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
