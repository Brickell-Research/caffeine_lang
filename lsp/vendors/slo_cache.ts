// TTL-based cache for SLO status data, keyed by dotted identifier.

import type { DatadogCredentials, SloStatus } from "./types.ts";
import { fetchCaffeineSlos } from "./datadog_client.ts";
import { debug } from "../debug.ts";

/** Cache TTL in milliseconds (5 minutes). */
const DEFAULT_TTL_MS = 300_000;

/** Refresh interval in milliseconds (5 minutes).
 *  Each refresh makes 1 list + N history API calls, so keep this conservative. */
const REFRESH_INTERVAL_MS = 300_000;

export class SloStatusCache {
  private data = new Map<string, SloStatus[]>();
  private lastFetchMs = 0;
  private ttlMs: number;
  private refreshTimer: ReturnType<typeof setInterval> | null = null;
  private fetching = false;
  private credentials: DatadogCredentials;
  private onRefresh: (() => void) | null = null;

  constructor(credentials: DatadogCredentials, ttlMs = DEFAULT_TTL_MS) {
    this.credentials = credentials;
    this.ttlMs = ttlMs;
  }

  /** Get cached SLO statuses by dotted identifier (one per timeframe window). */
  get(dottedId: string): SloStatus[] | null {
    return this.data.get(dottedId) ?? null;
  }

  /** Whether the cache has any data. */
  get hasData(): boolean {
    return this.data.size > 0;
  }

  /** Whether at least one fetch has completed (data may still be empty). */
  get hasFetched(): boolean {
    return this.lastFetchMs > 0;
  }

  /** Update credentials (e.g. after loading a .env file). */
  updateCredentials(credentials: DatadogCredentials): void {
    this.credentials = credentials;
  }

  /** Whether the cache is stale (past TTL). */
  get isStale(): boolean {
    return Date.now() - this.lastFetchMs > this.ttlMs;
  }

  /** Register a callback invoked after each successful refresh. */
  onDidRefresh(callback: () => void): void {
    this.onRefresh = callback;
  }

  /** Fetch SLO data from Datadog and update the cache. */
  async refresh(): Promise<void> {
    if (this.fetching) return;
    this.fetching = true;

    try {
      const slos = await fetchCaffeineSlos(this.credentials);
      this.data = slos;
      this.lastFetchMs = Date.now();
      debug(`slo-cache: refreshed, ${slos.size} SLOs cached`);
      this.onRefresh?.();
    } catch (e) {
      debug(`slo-cache: refresh error: ${e}`);
    } finally {
      this.fetching = false;
    }
  }

  /** Start periodic background refresh. */
  startPeriodicRefresh(): void {
    if (this.refreshTimer) return;
    this.refreshTimer = setInterval(() => {
      this.refresh();
    }, REFRESH_INTERVAL_MS);
  }

  /** Stop periodic background refresh. */
  stopPeriodicRefresh(): void {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  /** Ensure data is available — refresh if stale, otherwise return immediately. */
  async ensureFresh(): Promise<void> {
    if (this.isStale) {
      await this.refresh();
    }
  }
}
