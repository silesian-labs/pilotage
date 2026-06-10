import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Address } from "viem";
import { sql } from "./db.js";
import { readScores } from "./reputation.js";

export const app = new Hono();

app.use("*", cors());

app.get("/api/pilots", async (c) => {
  const risk = c.req.query("risk");
  const limit = Math.min(Number(c.req.query("limit") ?? 20), 100);
  const offset = Number(c.req.query("offset") ?? 0);

  const rows = await sql<{ operator: string }[]>`
    SELECT p.*
    FROM pilots p
    WHERE p.active = true
      AND p.slashed = false
      ${risk ? sql`AND p.risk_profile = ${risk}` : sql``}
    ORDER BY p.registered_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `;

  const scores = await readScores(rows.map((r) => r.operator as Address));
  const pilots = rows
    .map((p, i) => ({ ...p, pilotage_score: scores[i] }))
    .sort((a, b) => (b.pilotage_score ?? 0) - (a.pilotage_score ?? 0));

  return c.json({ pilots, total: pilots.length });
});

app.get("/api/pilots/:id", async (c) => {
  const id = Number(c.req.param("id"));
  const [pilot] = await sql<{ operator: string }[]>`
    SELECT p.* FROM pilots p WHERE p.id = ${id}
  `;
  if (!pilot) return c.json({ error: "not found" }, 404);

  const [score] = await readScores([pilot.operator as Address]);
  return c.json({ ...pilot, pilotage_score: score });
});

app.get("/api/vaults/:address", async (c) => {
  const address = c.req.param("address").toLowerCase();
  const [vault] = await sql`SELECT * FROM vaults WHERE address = ${address}`;
  if (!vault) return c.json({ error: "not found" }, 404);
  return c.json(vault);
});

app.get("/api/vaults/:address/actions", async (c) => {
  const address = c.req.param("address").toLowerCase();
  const limit = Math.min(Number(c.req.query("limit") ?? 50), 200);

  const actions = await sql`
    SELECT * FROM actions
    WHERE vault = ${address}
    ORDER BY executed_at DESC
    LIMIT ${limit}
  `;
  return c.json({ actions });
});

app.get("/api/stats", async (c) => {
  const [{ vault_count }] =
    await sql`SELECT COUNT(*) AS vault_count FROM vaults`;
  const [{ pilot_count }] =
    await sql`SELECT COUNT(*) AS pilot_count FROM pilots WHERE active = true`;
  const [{ action_count }] =
    await sql`SELECT COUNT(*) AS action_count FROM actions WHERE success = true`;

  return c.json({
    vaults: Number(vault_count),
    activePilots: Number(pilot_count),
    successfulActions: Number(action_count),
  });
});
