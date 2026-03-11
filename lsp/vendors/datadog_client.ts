// Minimal Datadog API client for fetching SLO status.

import type { DatadogCredentials, SloStatus } from "./types.ts";
import { debug } from "../debug.ts";

/** Raw SLO object from the Datadog API (partial — only fields we use). */
interface DatadogSloResponse {
  id: string;
  name: string;
  tags: string[];
  overall_status: Array<{
    sli_value: number | null;
    error_budget_remaining: number | null;
    target: number;
    timeframe: string;
  }>;
}

/** A fetched SLO with its parsed caffeine identity tags. */
export interface DatadogSloResult {
  id: string;
  name: string;
  dottedId: string | null;
  status: SloStatus | null;
}

/** Parse caffeine identity tags from a Datadog SLO's tags array.
 *  Tags are in "key:value" format. We extract org, team, service, expectation. */
export function parseCaffeineIdentity(tags: string[]): string | null {
  let org: string | null = null;
  let team: string | null = null;
  let service: string | null = null;
  let expectation: string | null = null;

  for (const tag of tags) {
    const colonIdx = tag.indexOf(":");
    if (colonIdx < 0) continue;
    const key = tag.slice(0, colonIdx);
    const value = tag.slice(colonIdx + 1);
    switch (key) {
      case "org": org = value; break;
      case "team": team = value; break;
      case "service": service = value; break;
      case "expectation": expectation = value; break;
    }
  }

  if (org && team && service && expectation) {
    return `${org}.${team}.${service}.${expectation}`;
  }
  return null;
}

/** Determine status category from SLI value vs target and error budget. */
export function categorizeStatus(
  sliValue: number,
  target: number,
  errorBudgetRemaining: number,
): "ok" | "warning" | "breaching" {
  if (sliValue < target || errorBudgetRemaining <= 0) return "breaching";
  if (errorBudgetRemaining < 20) return "warning";
  return "ok";
}

/** Convert Datadog timeframe string (e.g., "30d") to display format. */
function normalizeWindow(timeframe: string): string {
  return timeframe;
}

/** Fetch all caffeine-managed SLOs from Datadog.
 *  Returns a Map from dotted identifier to SloStatus. */
export async function fetchCaffeineSlos(
  credentials: DatadogCredentials,
): Promise<Map<string, SloStatus>> {
  const result = new Map<string, SloStatus>();
  const baseUrl = `https://api.${credentials.site}`;
  const url = `${baseUrl}/api/v1/slo?tags_query=managed_by:caffeine&limit=1000`;

  try {
    const response = await fetch(url, {
      headers: {
        "DD-API-KEY": credentials.apiKey,
        "DD-APPLICATION-KEY": credentials.appKey,
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      debug(`datadog: fetch failed ${response.status} ${response.statusText}`);
      return result;
    }

    const body = await response.json() as { data: DatadogSloResponse[] };
    const slos = body.data ?? [];
    debug(`datadog: fetched ${slos.length} caffeine-managed SLOs`);

    for (const slo of slos) {
      const dottedId = parseCaffeineIdentity(slo.tags);
      if (!dottedId) continue;

      // Use the first overall_status entry (typically the primary threshold)
      const primary = slo.overall_status?.[0];
      if (!primary || primary.sli_value == null) continue;

      const sliValue = primary.sli_value;
      const target = primary.target;
      const errorBudget = primary.error_budget_remaining ?? 0;

      result.set(dottedId, {
        sli_value: sliValue,
        target,
        error_budget_remaining: errorBudget,
        window: normalizeWindow(primary.timeframe),
        status: categorizeStatus(sliValue, target, errorBudget),
        dashboard_url: `https://app.${credentials.site}/slo?slo_id=${slo.id}`,
      });
    }
  } catch (e) {
    debug(`datadog: fetch error: ${e}`);
  }

  return result;
}
