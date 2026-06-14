import { config } from "./config.js";

export interface LlmInput {
  usdcValueUsd: number;
  aUsdcValueUsd: number;
  totalUsd: number;
  targetUsdcPct: number;
  driftBps: number;
  thresholdBps: number;
  direction: "supply" | "withdraw";
  maxAmountUsdc: number;
  maxSingleUsdc: number;
  maxDailyUsdc: number;
  dailySpentUsdc: number;
  aUsdcPriceUsd: number;
}

export interface LlmDecision {
  act: boolean;
  fraction: number; // 0..1 of the max corrective amount
  confidence: number; // 0..1 self-rated confidence
  urgency: "low" | "medium" | "high";
  reason: string; // short, demo-friendly summary
  analysis: string; // the engine's reasoning trace
}

// Minimum confidence required to act. Below this, the engine abstains even if
// it nominally said "act" — a real risk gate rather than blind execution.
const MIN_CONFIDENCE = 0.4;

const SYSTEM_INSTRUCTION = [
  "You are the decision engine of ConservativeRWA, an autonomous treasury pilot that",
  "rebalances a non-custodial on-chain vault between idle USDC and USDC supplied to",
  "Aave V3 (aUSDC). You do NOT have custody and you cannot move funds outside a signed",
  "charter (whitelisted venue, whitelisted tokens, a per-action cap, a daily cap, an expiry).",
  "Your single job each tick: decide whether a rebalance is worth executing right now and,",
  "if so, how large it should be.",
  "",
  "Operate like a careful risk manager, not a high-frequency trader. Reason explicitly about:",
  "  1. SIGNAL — how far the current drift is beyond the action threshold. Drift just over",
  "     the threshold is weak signal; drift far beyond it is strong.",
  "  2. ECONOMICS — the corrective trade costs gas and realizes a position change. A move that",
  "     is tiny relative to the total vault value is usually not worth the churn.",
  "  3. DIRECTION & PRICE — read the aUSDC mark carefully:",
  "       * aUSDC ABOVE $1.00 means the supplied position has APPRECIATED, so the vault is",
  "         overweight a winning asset. Trimming it back toward target (a 'withdraw') is prudent",
  "         profit-taking and de-risking — acting here is normal and usually correct.",
  "       * aUSDC BELOW $1.00 signals stress/de-peg risk. Be cautious about SUPPLYING more into a",
  "         falling asset; a smaller fraction or a hold can be justified.",
  "     Size the correction to the part of the drift you believe will persist rather than chasing",
  "     a possibly transient one-tick spike.",
  "  4. BUDGET — respect the remaining daily allowance. Never recommend an amount whose effect",
  "     would push the day's cumulative spend past the daily cap; prefer a partial move instead.",
  "  5. STABILITY — avoid overshooting the target. A fraction near 1.0 fully corrects; a smaller",
  "     fraction corrects gently and leaves room if the drift keeps growing.",
  "",
  "Be decisive on clear, meaningful drift and restrained on marginal noise. Always return your",
  "reasoning so a human watching the demo can audit the call.",
].join("\n");

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    analysis: { type: "string", description: "Concise reasoning across signal, economics, persistence, budget, stability." },
    act: { type: "boolean", description: "Whether to execute a rebalance now." },
    fraction: { type: "number", description: "Fraction (0..1) of the max corrective amount to move." },
    confidence: { type: "number", description: "Self-rated confidence 0..1 in this decision." },
    urgency: { type: "string", enum: ["low", "medium", "high"] },
    reason: { type: "string", description: "One short sentence (<120 chars) summarizing the call." },
  },
  required: ["analysis", "act", "fraction", "confidence", "urgency", "reason"],
};

export async function decideWithGemini(
  input: LlmInput,
): Promise<LlmDecision | null> {
  const key = config.geminiApiKey;
  if (!key) return null;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:generateContent?key=${key}`;

  // Pre-compute the real, decision-relevant signals so the model reasons over
  // numbers rather than guessing them.
  const overweight = input.direction === "withdraw" ? "aUSDC" : "idle USDC";
  const driftPct = (input.driftBps / 100).toFixed(2);
  const thresholdPct = (input.thresholdBps / 100).toFixed(2);
  const excessOverThreshold = ((input.driftBps - input.thresholdBps) / 100).toFixed(2);
  const moveAsPctOfVault = input.totalUsd > 0
    ? ((input.maxAmountUsdc / input.totalUsd) * 100).toFixed(2)
    : "0.00";
  const remainingDailyUsdc = Math.max(0, input.maxDailyUsdc - input.dailySpentUsdc);
  const priceDeviationPct = ((input.aUsdcPriceUsd - 1) * 100).toFixed(2);

  const userPrompt = [
    "TICK SNAPSHOT",
    `- idle USDC value:      $${input.usdcValueUsd.toFixed(2)}`,
    `- aUSDC value:          $${input.aUsdcValueUsd.toFixed(2)}`,
    `- total vault value:    $${input.totalUsd.toFixed(2)}`,
    `- target split:         ${input.targetUsdcPct}% USDC / ${100 - input.targetUsdcPct}% aUSDC`,
    `- current max drift:    ${input.driftBps} bps (${driftPct}%)`,
    `- action threshold:     ${input.thresholdBps} bps (${thresholdPct}%)`,
    `- drift beyond threshold: ${excessOverThreshold}%`,
    `- overweight asset:     ${overweight}`,
    `- aUSDC oracle mark:    $${input.aUsdcPriceUsd.toFixed(4)} (${priceDeviationPct}% off peg)`,
    "",
    "PROPOSED CORRECTION",
    `- direction:            ${input.direction} (${input.direction === "supply" ? "idle USDC -> Aave" : "aUSDC -> idle USDC"})`,
    `- max corrective amount: ${input.maxAmountUsdc.toFixed(2)} USDC (= ${moveAsPctOfVault}% of vault)`,
    "",
    "CHARTER CONSTRAINTS",
    `- per-action cap:       ${input.maxSingleUsdc.toFixed(2)} USDC`,
    `- daily cap:            ${input.maxDailyUsdc.toFixed(2)} USDC`,
    `- already spent today:  ${input.dailySpentUsdc.toFixed(2)} USDC`,
    `- remaining today:      ${remainingDailyUsdc.toFixed(2)} USDC`,
    "",
    "FRACTION MEANING: 'fraction' multiplies the max corrective amount above (NOT a % of the vault).",
    "  fraction 1.0 = move the full corrective amount and fully restore the target split;",
    "  fraction 0.5 = close about half the gap. For a clear, persistent drift well beyond the",
    "  threshold, a decisive fraction (typically 0.7–1.0) is appropriate. Reserve low fractions",
    "  (<0.4) for marginal drift only just past the threshold or a likely-transient one-tick spike.",
    "Always keep the resulting move within the remaining daily allowance.",
    "",
    "Work through signal, economics, direction & price, budget and stability, then return your decision.",
  ].join("\n");

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
        contents: [{ role: "user", parts: [{ text: userPrompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
          temperature: 0.2,
          maxOutputTokens: 512,
        },
      }),
    });

    if (!res.ok) {
      console.warn(`[llm] Gemini ${res.status} — falling back to rule-based`);
      return null;
    }

    const data = (await res.json()) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
    };
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) return null;

    const parsed = JSON.parse(text) as Partial<LlmDecision>;
    const confidence = clamp(Number(parsed.confidence ?? 0.5), 0, 1);
    const wantsToAct = Boolean(parsed.act);

    // Risk gate: a low-confidence "act" is downgraded to a hold.
    const act = wantsToAct && confidence >= MIN_CONFIDENCE;

    return {
      act,
      fraction: clamp(Number(parsed.fraction ?? 1), 0, 1),
      confidence,
      urgency: normalizeUrgency(parsed.urgency),
      reason: String(parsed.reason ?? "").slice(0, 160),
      analysis: String(parsed.analysis ?? "").slice(0, 600),
    };
  } catch (err) {
    console.warn("[llm] error — falling back to rule-based:", err);
    return null;
  }
}

function normalizeUrgency(u: unknown): "low" | "medium" | "high" {
  return u === "high" || u === "medium" || u === "low" ? u : "medium";
}

function clamp(n: number, lo: number, hi: number): number {
  if (Number.isNaN(n)) return hi;
  return Math.max(lo, Math.min(hi, n));
}
