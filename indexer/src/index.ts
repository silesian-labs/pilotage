import { serve } from "@hono/node-server";
import { app } from "./api.js";
import { migrate } from "./db.js";
import {
  watchVaultCreated,
  watchPilotRegistered,
  startActionWatcher,
  loadKnownVaults,
  syncHistorical,
} from "./events.js";

const PORT = Number(process.env.PORT ?? 3001);

async function main() {
  await migrate();

  const fromBlock = BigInt(process.env.INDEXER_FROM_BLOCK ?? "0");
  await syncHistorical(fromBlock);

  const knownVaults = await loadKnownVaults();
  console.log(`[indexer] loaded ${knownVaults.length} vault(s)`);

  const unwatchers = [
    watchVaultCreated(),
    watchPilotRegistered(),
    startActionWatcher(knownVaults),
  ];

  serve({ fetch: app.fetch, port: PORT }, () => {
    console.log(`[indexer] API at http://localhost:${PORT}`);
  });

  const shutdown = () => {
    unwatchers.forEach((u) => u());
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
