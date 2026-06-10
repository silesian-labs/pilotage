import {
  createPublicClient,
  http,
  type Address,
  type PublicClient,
} from "viem";
import {
  VAULT_FACTORY_ABI,
  PILOT_REGISTRY_ABI,
  VAULT_ABI,
} from "@pilotage/pilot-sdk";
import { sql } from "./db.js";

function required(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

const CHAIN_ID = Number(process.env.CHAIN_ID ?? "421614");
const RPC_URL = required("ARBITRUM_SEPOLIA_RPC");
const FACTORY = required("VAULT_FACTORY") as Address;
const REGISTRY = required("PILOT_REGISTRY") as Address;

const client: PublicClient = createPublicClient({ transport: http(RPC_URL) });

let unwatchActions: () => void = () => {};
let watchedVaults: Address[] = [];

function restartActionWatcher(vaults: Address[]) {
  unwatchActions();
  watchedVaults = vaults;
  if (vaults.length === 0) return;

  unwatchActions = client.watchContractEvent({
    address: vaults,
    abi: VAULT_ABI,
    eventName: "ActionExecuted",
    onLogs: async (logs) => {
      for (const log of logs) {
        const { pilot, action, success } = log.args as {
          pilot: Address;
          action: {
            target: Address;
            callData: `0x${string}`;
            value: bigint;
            tokenIn: Address;
            amountIn: bigint;
            tokenOut: Address;
          };
          success: boolean;
        };

        const vault = log.address.toLowerCase();
        const txHash = log.transactionHash ?? "0x";
        const blockNumber = Number(log.blockNumber ?? 0n);

        console.log(
          `[indexer] ActionExecuted vault=${vault} ${success ? "✓" : "✗"} tx=${txHash.slice(0, 10)}`,
        );

        await sql`
          INSERT INTO actions
            (vault, pilot, tx_hash, token_in, amount_in, token_out, success, chain_id, block_number)
          VALUES (
            ${vault}, ${pilot.toLowerCase()}, ${txHash},
            ${action.tokenIn.toLowerCase()}, ${action.amountIn.toString()},
            ${action.tokenOut.toLowerCase()}, ${success}, ${CHAIN_ID}, ${blockNumber}
          )
          ON CONFLICT (tx_hash) DO NOTHING
        `;
      }
    },
  });
}

export function watchVaultCreated(): () => void {
  return client.watchContractEvent({
    address: FACTORY,
    abi: VAULT_FACTORY_ABI,
    eventName: "VaultCreated",
    onLogs: async (logs) => {
      for (const log of logs) {
        const { captain, vault } = log.args as {
          captain: Address;
          vault: Address;
        };
        console.log(`[indexer] VaultCreated: ${vault}`);

        await sql`
          INSERT INTO vaults (address, captain, chain_id)
          VALUES (${vault.toLowerCase()}, ${captain.toLowerCase()}, ${CHAIN_ID})
          ON CONFLICT (address) DO NOTHING
        `;

        restartActionWatcher([...watchedVaults, vault]);
      }
    },
  });
}

export function watchPilotRegistered(): () => void {
  return client.watchContractEvent({
    address: REGISTRY,
    abi: PILOT_REGISTRY_ABI,
    eventName: "PilotRegistered",
    onLogs: async (logs) => {
      for (const log of logs) {
        const { id, developer, executor, operator, name } = log.args as {
          id: bigint;
          developer: Address;
          executor: Address;
          operator: Address;
          name: string;
        };

        console.log(`[indexer] PilotRegistered: ${name} (id ${id})`);

        const record = await client.readContract({
          address: REGISTRY,
          abi: PILOT_REGISTRY_ABI,
          functionName: "getPilot",
          args: [id],
        });

        await sql`
          INSERT INTO pilots
            (id, developer, executor, operator, name, risk_profile, description,
             ipfs_metadata, staked_amount, active, slashed, chain_id)
          VALUES (
            ${Number(id)}, ${developer.toLowerCase()}, ${executor.toLowerCase()},
            ${operator.toLowerCase()},
            ${record.card.name}, ${record.card.riskProfile}, ${record.card.description},
            ${record.card.ipfsMetadata}, ${record.stakedAmount.toString()},
            ${record.active}, ${record.slashed}, ${CHAIN_ID}
          )
          ON CONFLICT (id) DO UPDATE SET
            active        = EXCLUDED.active,
            slashed       = EXCLUDED.slashed,
            description   = EXCLUDED.description,
            ipfs_metadata = EXCLUDED.ipfs_metadata
        `;
      }
    },
  });
}

export function startActionWatcher(initialVaults: Address[]): () => void {
  restartActionWatcher(initialVaults);
  return () => unwatchActions();
}

export async function loadKnownVaults(): Promise<Address[]> {
  const rows = await sql<{ address: string }[]>`
    SELECT address FROM vaults WHERE chain_id = ${CHAIN_ID}
  `;
  return rows.map((r) => r.address as Address);
}

export async function syncHistorical(
  fromBlock: bigint = 0n,
): Promise<Address[]> {
  console.log(`[indexer] syncing historical events from block ${fromBlock}…`);

  const [vaultLogs, pilotLogs] = await Promise.all([
    client.getLogs({
      address: FACTORY,
      event: VAULT_FACTORY_ABI.find(
        (e) => e.type === "event" && e.name === "VaultCreated",
      ) as any,
      fromBlock,
      toBlock: "latest",
    }),
    client.getLogs({
      address: REGISTRY,
      event: PILOT_REGISTRY_ABI.find(
        (e) => e.type === "event" && e.name === "PilotRegistered",
      ) as any,
      fromBlock,
      toBlock: "latest",
    }),
  ]);

  const vaults: Address[] = [];

  for (const log of vaultLogs) {
    const { captain, vault } = (log as any).args as {
      captain: Address;
      vault: Address;
    };
    console.log(`[indexer] (historical) VaultCreated: ${vault}`);
    await sql`
      INSERT INTO vaults (address, captain, chain_id)
      VALUES (${vault.toLowerCase()}, ${captain.toLowerCase()}, ${CHAIN_ID})
      ON CONFLICT (address) DO NOTHING
    `;
    vaults.push(vault);
  }

  for (const log of pilotLogs) {
    const { id, developer, executor, operator, name } = (log as any).args as {
      id: bigint;
      developer: Address;
      executor: Address;
      operator: Address;
      name: string;
    };
    console.log(`[indexer] (historical) PilotRegistered: ${name} (id ${id})`);

    const record = await client.readContract({
      address: REGISTRY,
      abi: PILOT_REGISTRY_ABI,
      functionName: "getPilot",
      args: [id],
    });

    await sql`
      INSERT INTO pilots
        (id, developer, executor, operator, name, risk_profile, description,
         ipfs_metadata, staked_amount, active, slashed, chain_id)
      VALUES (
        ${Number(id)}, ${developer.toLowerCase()}, ${executor.toLowerCase()},
        ${operator.toLowerCase()},
        ${record.card.name}, ${record.card.riskProfile}, ${record.card.description},
        ${record.card.ipfsMetadata}, ${record.stakedAmount.toString()},
        ${record.active}, ${record.slashed}, ${CHAIN_ID}
      )
      ON CONFLICT (id) DO UPDATE SET
        active        = EXCLUDED.active,
        slashed       = EXCLUDED.slashed,
        description   = EXCLUDED.description,
        ipfs_metadata = EXCLUDED.ipfs_metadata
    `;
  }

  console.log(
    `[indexer] historical sync done: ${vaults.length} vault(s), ${pilotLogs.length} pilot(s)`,
  );
  return vaults;
}
