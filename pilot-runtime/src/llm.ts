import { config } from "./config.js";

export interface LlmInput {
  usdcValueUsd: number;
  aUsdcValueUsd: number;
  totalUsd: number;
  targetUsdcPct: number;
  driftBps: number;
  direction: "supply" | "withdraw";
  maxAmountUsdc: number;
}

export interface LlmDecision {
  act: boolean;
  fraction: number;
  reason: string;
}

export async function decideWithGemini(
  input: LlmInput,
): Promise<LlmDecision | null> {
  const key = config.geminiApiKey;
  if (!key) return null;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:generateContent?key=${key}`;

  const prompt = [
    "You are ConservativeRWA, a cautious DeFi rebalancing pilot managing a non-custodial vault.",
    "The vault holds idle USDC and USDC supplied to Aave V3 (aUSDC).",
    `Target allocation: ${input.targetUsdcPct}% idle USDC / ${100 - input.targetUsdcPct}% aUSDC.`,
    "",
    "Current state:",
    `- idle USDC value: $${input.usdcValueUsd.toFixed(2)}`,
    `- aUSDC value:     $${input.aUsdcValueUsd.toFixed(2)}`,
    `- total value:     $${input.totalUsd.toFixed(2)}`,
    `- max drift:       ${input.driftBps} bps (threshold to act is 500 bps)`,
    "",
    `The corrective move is to ${input.direction} up to ${input.maxAmountUsdc.toFixed(2)} USDC`,
    `(${input.direction === "supply" ? "idle USDC into Aave" : "aUSDC back to idle USDC"}).`,
    "",
    "Decide whether to act now and what fraction (0..1) of the max amount to move.",
    "Be conservative: avoid churn on small drifts, but correct meaningful drift toward target.",
    'Respond ONLY as JSON: {"act": boolean, "fraction": number, "reason": string}.',
    "Keep reason under 120 characters.",
  ].join("\n");

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.2,
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
    return {
      act: Boolean(parsed.act),
      fraction: clamp(Number(parsed.fraction ?? 1), 0, 1),
      reason: String(parsed.reason ?? "").slice(0, 200),
    };
  } catch (err) {
    console.warn("[llm] error — falling back to rule-based:", err);
    return null;
  }
}

function clamp(n: number, lo: number, hi: number): number {
  if (Number.isNaN(n)) return hi;
  return Math.max(lo, Math.min(hi, n));
}
