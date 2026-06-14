import { Pilot } from "@pilotage/pilot-sdk";
import { config } from "./config.js";
import { makeConservativeRWAStrategy } from "./strategy.js";

const strategy = makeConservativeRWAStrategy(
  config.executorAddress,
  config.aavePool,
  config.usdc,
  config.aUsdc,
);

const pilot = new Pilot(strategy, {
  vaultAddress: config.vaultAddress,
  vaultFactory: config.vaultFactory,
  discoveryIntervalMs: config.discoveryIntervalMs,
  pilotPrivateKey: config.pilotPrivateKey,
  oracleAddress: config.oracleAddress,
  tokens: [config.usdc, config.aUsdc],
  targetsBps: config.targetsBps,
  rpcUrl: config.rpcUrl,
  pollIntervalMs: config.pollIntervalMs,
  chainId: config.chainId,
});

process.on("SIGINT", () => {
  pilot.stop();
  process.exit(0);
});
process.on("SIGTERM", () => {
  pilot.stop();
  process.exit(0);
});

pilot.run().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
