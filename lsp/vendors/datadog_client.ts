// Minimal Datadog API client for fetching SLO status.

import type { DatadogCredentials, SloStatus } from "./types.ts";
import { debug } from "../debug.ts";

/** Raw SLO object from the Datadog list API. */
interface DatadogSloListEntry {
  id: string;
  name: string;
  tags: string[];
  thresholds: Array<{
    timeframe: string;
    target: number;
    target_display: string;
  }>;
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

/** Calculate error budget remaining as a percentage.
 *  Formula: ((sli - target) / (100 - target)) * 100 */
function calcErrorBudget(sliValue: number, target: number): number {
  const errorBudgetTotal = 100 - target;
  if (errorBudgetTotal <= 0) return 0;
  return ((sliValue - target) / errorBudgetTotal) * 100;
}

/** Convert timeframe string (e.g., "7d") to seconds. */
function timeframeToSeconds(timeframe: string): number {
  const match = timeframe.match(/^(\d+)d$/);
  if (match) return parseInt(match[1], 10) * 86400;
  // Fallback: 30 days
  return 30 * 86400;
}

/** Standard headers for Datadog API requests. */
function ddHeaders(credentials: DatadogCredentials): Record<string, string> {
  return {
    "DD-API-KEY": credentials.apiKey,
    "DD-APPLICATION-KEY": credentials.appKey,
    "Content-Type": "application/json",
  };
}

/** Timeout for individual Datadog API requests (10 seconds). */
const REQUEST_TIMEOUT_MS = 10_000;

/** Fetch all caffeine-managed SLOs from Datadog.
 *  Two-phase: list SLOs by tag to get IDs/thresholds, then fetch history for SLI values.
 *  Returns a Map from dotted identifier to SloStatus array (one per timeframe window). */
export async function fetchCaffeineSlos(
  credentials: DatadogCredentials,
): Promise<Map<string, SloStatus[]>> {
  const result = new Map<string, SloStatus[]>();
  const baseUrl = `https://api.${credentials.site}`;
  const headers = ddHeaders(credentials);

  try {
    // Phase 1: List caffeine-managed SLOs to get IDs, tags, and thresholds
    const listUrl = `${baseUrl}/api/v1/slo?tags_query=managed_by:caffeine&limit=1000`;
    const listResponse = await fetch(listUrl, { headers, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });

    if (!listResponse.ok) {
      const body = await listResponse.text().catch(() => "(unreadable)");
      debug(`datadog: list failed ${listResponse.status} ${listResponse.statusText}: ${body}`);
      return result;
    }

    const listBody = await listResponse.json() as { data: DatadogSloListEntry[] };
    const sloList = listBody.data ?? [];
    debug(`datadog: listed ${sloList.length} caffeine-managed SLOs`);
    if (sloList.length >= 1000) {
      debug("datadog: WARNING — response hit 1000 limit, some SLOs may be missing");
    }

    // Build work items: SLO ID → { dottedId, thresholds }
    interface SloWorkItem {
      id: string;
      name: string;
      dottedId: string;
      thresholds: DatadogSloListEntry["thresholds"];
    }
    const workItems: SloWorkItem[] = [];

    for (const slo of sloList) {
      const dottedId = parseCaffeineIdentity(slo.tags ?? []);
      if (dottedId) {
        workItems.push({
          id: slo.id,
          name: slo.name,
          dottedId,
          thresholds: slo.thresholds ?? [],
        });
      }
    }
    debug(`datadog: ${workItems.length} SLOs have valid caffeine identity tags`);
    if (workItems.length === 0) return result;

    // Phase 2: Fetch SLO history for all SLOs in parallel to get actual SLI values.
    // The list/detail endpoints don't include current SLI — only the history endpoint does.
    // 56 parallel requests is well within Datadog's 300 req/min rate limit.
    const nowSec = Math.floor(Date.now() / 1000);

    await Promise.all(workItems.map(async (item) => {
      try {
        const thresholds = item.thresholds;
        if (thresholds.length === 0) return;

        // Pick the longest timeframe to fetch history for
        let maxSeconds = 0;
        for (const t of thresholds) {
          const sec = timeframeToSeconds(t.timeframe);
          if (sec > maxSeconds) maxSeconds = sec;
        }
        const fromTs = nowSec - maxSeconds;

        const historyUrl = `${baseUrl}/api/v1/slo/${item.id}/history?from_ts=${fromTs}&to_ts=${nowSec}`;
        const resp = await fetch(historyUrl, { headers, signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) });
        if (!resp.ok) {
          debug(`datadog: history ${item.id} failed ${resp.status}`);
          return;
        }

        // deno-lint-ignore no-explicit-any
        const body = await resp.json() as { data: any; errors: any };

        const dashboardUrl = `https://app.${credentials.site}/slo?slo_id=${item.id}`;
        const statuses: SloStatus[] = [];

        // Extract SLI from the history response.
        const historyData = body.data;
        if (!historyData?.overall) return;

        const overall = historyData.overall;
        const sliValue = overall.sli_value;
        if (typeof sliValue !== "number") return;

        // error_budget_remaining is an object like {"custom": 100} or {"7d": 85.3}
        // Extract the first numeric value; fall back to calculating from SLI and target
        let ddErrorBudget: number | null = null;
        const ebrObj = overall.error_budget_remaining;
        if (ebrObj && typeof ebrObj === "object") {
          for (const val of Object.values(ebrObj)) {
            if (typeof val === "number") { ddErrorBudget = val; break; }
          }
        }

        for (const threshold of thresholds) {
          const errorBudget = ddErrorBudget ?? calcErrorBudget(sliValue, threshold.target);
          statuses.push({
            sli_value: sliValue,
            target: threshold.target,
            error_budget_remaining: errorBudget,
            window: threshold.timeframe,
            status: categorizeStatus(sliValue, threshold.target, errorBudget),
            dashboard_url: dashboardUrl,
          });
        }

        if (statuses.length > 0) {
          result.set(item.dottedId, statuses);
        }
      } catch (e) {
        debug(`datadog: history ${item.id} error: ${e}`);
      }
    }));
  } catch (e) {
    debug(`datadog: fetch error: ${e}`);
  }

  return result;
}
