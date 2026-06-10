import postgres from "postgres";

function required(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

export const sql = postgres(required("DATABASE_URL"), {
  max: 10,
  onnotice: () => {},
});

export async function migrate(): Promise<void> {
  await sql`
    CREATE TABLE IF NOT EXISTS vaults (
      address    TEXT PRIMARY KEY,
      captain    TEXT NOT NULL,
      chain_id   INTEGER NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS pilots (
      id            INTEGER PRIMARY KEY,
      developer     TEXT NOT NULL,
      executor      TEXT NOT NULL,
      operator      TEXT NOT NULL,
      name          TEXT NOT NULL,
      risk_profile  TEXT NOT NULL,
      description   TEXT NOT NULL,
      ipfs_metadata TEXT NOT NULL DEFAULT '',
      staked_amount TEXT NOT NULL,
      active        BOOLEAN NOT NULL DEFAULT true,
      slashed       BOOLEAN NOT NULL DEFAULT false,
      chain_id      INTEGER NOT NULL,
      registered_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS actions (
      id           SERIAL PRIMARY KEY,
      vault        TEXT NOT NULL,
      pilot        TEXT NOT NULL,
      tx_hash      TEXT NOT NULL UNIQUE,
      token_in     TEXT NOT NULL,
      amount_in    TEXT NOT NULL,
      token_out    TEXT NOT NULL,
      success      BOOLEAN NOT NULL,
      chain_id     INTEGER NOT NULL,
      block_number BIGINT NOT NULL,
      executed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;

  await sql`CREATE INDEX IF NOT EXISTS actions_vault_idx ON actions(vault)`;
  await sql`CREATE INDEX IF NOT EXISTS actions_pilot_idx ON actions(pilot)`;

  console.log("[db] schema ready");
}
