// Shared types for vendor SLO integrations.

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
