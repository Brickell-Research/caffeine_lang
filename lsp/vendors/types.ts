// Shared types for vendor SLO integrations.

import fs from "node:fs";
import path from "node:path";

/** Normalized SLO status from any vendor. */
export interface SloStatus {
  sli_value: number;
  target: number;
  error_budget_remaining: number;
  window: string;
  status: "ok" | "warning" | "breaching";
  /** URL to the SLO dashboard in the vendor's UI, if available. */
  dashboard_url: string | null;
}

/** Datadog API credentials from environment variables. */
export interface DatadogCredentials {
  apiKey: string;
  appKey: string;
  site: string;
}

/** Load a .env file into process.env. Values from the file override existing env vars. */
export function loadEnvFile(dir: string): void {
  const envPath = path.join(dir, ".env");
  let content: string;
  try {
    content = fs.readFileSync(envPath, "utf-8");
  } catch {
    return;
  }
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    let value = trimmed.slice(eqIdx + 1).trim();
    // Strip surrounding quotes
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

/** Read Datadog credentials from environment variables. Returns null if not configured. */
export function getDatadogCredentials(): DatadogCredentials | null {
  const apiKey = process.env.DD_API_KEY;
  const appKey = process.env.DD_APP_KEY;
  if (!apiKey || !appKey) return null;
  return {
    apiKey,
    appKey,
    site: process.env.DD_SITE ?? "datadoghq.com",
  };
}
