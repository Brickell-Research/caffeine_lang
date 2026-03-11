/**
 * Unit tests for SLO overlay pure functions — tag parsing, status
 * categorization, vendor extraction, expectation positions, formatting.
 */

import { expect, test, describe } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { parseCaffeineIdentity, categorizeStatus } from "../../lsp/vendors/datadog_client.ts";
import { extractVendors } from "../../lsp/workspace_parsers.ts";
import { extractExpectationPositions, formatSloLensTitle } from "../../lsp/document_features.ts";
import { SloStatusCache } from "../../lsp/vendors/slo_cache.ts";
import { loadEnvFile } from "../../lsp/vendors/types.ts";

// ==== parseCaffeineIdentity ====
// * builds dotted ID from complete tag set
// * returns null when tags are incomplete
// * ignores unrelated tags
// * handles tags with colons in values

describe("parseCaffeineIdentity", () => {
  test("builds dotted identifier from complete caffeine tags", () => {
    const tags = [
      "managed_by:caffeine",
      "org:acme",
      "team:platform",
      "service:api-gateway",
      "expectation:p99-latency",
    ];
    expect(parseCaffeineIdentity(tags)).toBe("acme.platform.api-gateway.p99-latency");
  });

  test("returns null when org tag is missing", () => {
    const tags = ["team:platform", "service:api", "expectation:p99"];
    expect(parseCaffeineIdentity(tags)).toBeNull();
  });

  test("returns null when team tag is missing", () => {
    const tags = ["org:acme", "service:api", "expectation:p99"];
    expect(parseCaffeineIdentity(tags)).toBeNull();
  });

  test("returns null when service tag is missing", () => {
    const tags = ["org:acme", "team:platform", "expectation:p99"];
    expect(parseCaffeineIdentity(tags)).toBeNull();
  });

  test("returns null when expectation tag is missing", () => {
    const tags = ["org:acme", "team:platform", "service:api"];
    expect(parseCaffeineIdentity(tags)).toBeNull();
  });

  test("returns null for empty tags array", () => {
    expect(parseCaffeineIdentity([])).toBeNull();
  });

  test("ignores unrelated tags", () => {
    const tags = [
      "managed_by:caffeine",
      "env:production",
      "org:acme",
      "team:platform",
      "service:api",
      "expectation:p99",
      "region:us-east-1",
    ];
    expect(parseCaffeineIdentity(tags)).toBe("acme.platform.api.p99");
  });

  test("handles tags without colons gracefully", () => {
    const tags = ["no-colon-tag", "org:acme", "team:x", "service:y", "expectation:z"];
    expect(parseCaffeineIdentity(tags)).toBe("acme.x.y.z");
  });
});

// ==== categorizeStatus ====
// * breaching when SLI below target
// * breaching when error budget depleted
// * warning when error budget low
// * ok when healthy

describe("categorizeStatus", () => {
  test("returns breaching when SLI is below target", () => {
    expect(categorizeStatus(99.0, 99.9, 50)).toBe("breaching");
  });

  test("returns breaching when error budget is zero", () => {
    expect(categorizeStatus(99.95, 99.9, 0)).toBe("breaching");
  });

  test("returns breaching when error budget is negative", () => {
    expect(categorizeStatus(99.95, 99.9, -5)).toBe("breaching");
  });

  test("returns warning when error budget is below 20%", () => {
    expect(categorizeStatus(99.95, 99.9, 10)).toBe("warning");
  });

  test("returns warning at error budget boundary (19.9%)", () => {
    expect(categorizeStatus(99.95, 99.9, 19.9)).toBe("warning");
  });

  test("returns ok when healthy", () => {
    expect(categorizeStatus(99.99, 99.9, 80)).toBe("ok");
  });

  test("returns ok at error budget boundary (20%)", () => {
    expect(categorizeStatus(99.95, 99.9, 20)).toBe("ok");
  });

  test("returns breaching when SLI equals target but budget is zero", () => {
    expect(categorizeStatus(99.9, 99.9, 0)).toBe("breaching");
  });
});

// ==== extractVendors ====
// * extracts vendor from blueprint Provides
// * extracts vendor from expects Provides
// * handles multiple items with different vendors
// * resolves vendor through extends chain
// * resolves vendor through multiple extends (first wins)
// * direct vendor overrides extended vendor
// * skips comments
// * returns empty map for files without vendors

describe("extractVendors", () => {
  test("extracts vendor from blueprint Provides", () => {
    const text = `Blueprints for "SLO"
  * "api-latency":
    Requires { env: String }
    Provides {
      vendor: "datadog",
      threshold: 99.9%
    }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(1);
    expect(vendors.get("api-latency")).toBe("datadog");
  });

  test("extracts vendor from expects Provides", () => {
    const text = `Expectations for "slo-blueprint"
  * "p99-latency":
    Provides {
      vendor: "honeycomb",
      env: "production"
    }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(1);
    expect(vendors.get("p99-latency")).toBe("honeycomb");
  });

  test("handles multiple items with different vendors", () => {
    const text = `Blueprints for "SLO"
  * "dd-slo":
    Requires { env: String }
    Provides {
      vendor: "datadog",
      threshold: 99.9%
    }
  * "hc-slo":
    Requires { env: String }
    Provides {
      vendor: "honeycomb",
      threshold: 99.5%
    }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(2);
    expect(vendors.get("dd-slo")).toBe("datadog");
    expect(vendors.get("hc-slo")).toBe("honeycomb");
  });

  test("skips commented lines", () => {
    const text = `Blueprints for "SLO"
  # * "commented-out":
  #   Provides { vendor: "datadog" }
  * "real":
    Provides { vendor: "honeycomb" }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(1);
    expect(vendors.get("real")).toBe("honeycomb");
    expect(vendors.has("commented-out")).toBe(false);
  });

  test("returns empty map for file without vendors", () => {
    const text = `Blueprints for "SLO"
  * "no-vendor":
    Requires { env: String }
    Provides { threshold: 99.9% }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(0);
  });

  test("returns empty map for empty text", () => {
    expect(extractVendors("").size).toBe(0);
  });

  test("resolves vendor through single extends", () => {
    const text = `_defaults (Provides): { vendor: "datadog" }

Expectations for "test_blueprint"
  * "checkout" extends [_defaults]:
    Provides { threshold: 99.9 }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(1);
    expect(vendors.get("checkout")).toBe("datadog");
  });

  test("resolves vendor through extends in blueprint file", () => {
    const text = `_base (Provides): { vendor: "datadog" }

Blueprints for "SLO"
  * "api-latency" extends [_base]:
    Requires { env: String }
    Provides { threshold: 99.9% }`;
    const vendors = extractVendors(text);
    expect(vendors.size).toBe(1);
    expect(vendors.get("api-latency")).toBe("datadog");
  });

  test("resolves vendor from first matching extends", () => {
    const text = `_no_vendor (Provides): { threshold: 99.0 }
_dd (Provides): { vendor: "datadog" }

Expectations for "bp"
  * "item" extends [_no_vendor, _dd]:
    Provides { env: "prod" }`;
    const vendors = extractVendors(text);
    expect(vendors.get("item")).toBe("datadog");
  });

  test("direct vendor overrides extended vendor", () => {
    const text = `_base (Provides): { vendor: "datadog" }

Expectations for "bp"
  * "item" extends [_base]:
    Provides { vendor: "honeycomb" }`;
    const vendors = extractVendors(text);
    expect(vendors.get("item")).toBe("honeycomb");
  });

  test("handles multi-line extendable definition", () => {
    const text = `_base (Provides): {
  vendor: "datadog",
  window_in_days: 30
}

Blueprints for "SLO"
  * "api" extends [_base]:
    Requires { env: String }
    Provides { threshold: 99.9% }`;
    const vendors = extractVendors(text);
    expect(vendors.get("api")).toBe("datadog");
  });
});

// ==== extractExpectationPositions ====
// * finds expectation items with line numbers
// * returns empty for non-expects files
// * skips commented items

describe("extractExpectationPositions", () => {
  test("finds expectation items with correct line numbers", () => {
    const text = `Expectations for "my-blueprint"
  * "first-item":
    Provides { env: "prod" }
  * "second-item":
    Provides { env: "staging" }`;
    const positions = extractExpectationPositions(text);
    expect(positions.length).toBe(2);
    expect(positions[0]).toEqual({ name: "first-item", line: 1 });
    expect(positions[1]).toEqual({ name: "second-item", line: 3 });
  });

  test("returns empty for blueprint files", () => {
    const text = `Blueprints for "SLO"
  * "item":
    Requires { env: String }
    Provides { vendor: "datadog" }`;
    const positions = extractExpectationPositions(text);
    expect(positions.length).toBe(0);
  });

  test("returns empty for empty text", () => {
    expect(extractExpectationPositions("").length).toBe(0);
  });

  test("skips commented items", () => {
    const text = `Expectations for "bp"
  * "active":
    Provides { env: "prod" }
  # * "commented":
  #   Provides { env: "dev" }`;
    const positions = extractExpectationPositions(text);
    expect(positions.length).toBe(1);
    expect(positions[0].name).toBe("active");
  });
});

// ==== formatSloLensTitle ====
// * formats ok status
// * formats warning status with icon
// * formats breaching status with icon

describe("formatSloLensTitle", () => {
  test("formats ok status without warning icon", () => {
    const title = formatSloLensTitle({
      sli_value: 99.95,
      target: 99.9,
      error_budget_remaining: 50.0,
      window: "30d",
      status: "ok",
    });
    expect(title).toBe("SLI: 99.95% | Target: 99.9% | Budget: 50.0% remaining | 30d");
  });

  test("formats warning status with warning icon", () => {
    const title = formatSloLensTitle({
      sli_value: 99.92,
      target: 99.9,
      error_budget_remaining: 15.3,
      window: "7d",
      status: "warning",
    });
    expect(title).toContain("Budget: 15.3% remaining");
    expect(title).toContain("\u26A0\uFE0F"); // warning emoji
    expect(title).not.toContain("\uD83D\uDD34"); // no red circle
  });

  test("formats breaching status with red circle icon", () => {
    const title = formatSloLensTitle({
      sli_value: 99.50,
      target: 99.9,
      error_budget_remaining: -10.5,
      window: "30d",
      status: "breaching",
    });
    expect(title).toContain("SLI: 99.50%");
    expect(title).toContain("\uD83D\uDD34"); // red circle
  });

  test("formats values with correct decimal precision", () => {
    const title = formatSloLensTitle({
      sli_value: 100,
      target: 99.0,
      error_budget_remaining: 100,
      window: "90d",
      status: "ok",
    });
    expect(title).toBe("SLI: 100.00% | Target: 99.0% | Budget: 100.0% remaining | 90d");
  });
});

// ==== SloStatusCache ====
// * get returns null for unknown keys
// * hasData reflects cache state
// * isStale after TTL expires

describe("SloStatusCache", () => {
  // Use fake credentials — no actual API calls in these tests
  const fakeCreds = { apiKey: "fake", appKey: "fake", site: "datadoghq.com" };

  test("get returns null for unknown dotted ID", () => {
    const cache = new SloStatusCache(fakeCreds);
    expect(cache.get("org.team.svc.name")).toBeNull();
  });

  test("hasData is false when cache is empty", () => {
    const cache = new SloStatusCache(fakeCreds);
    expect(cache.hasData).toBe(false);
  });

  test("isStale is true when cache has never been refreshed", () => {
    const cache = new SloStatusCache(fakeCreds);
    expect(cache.isStale).toBe(true);
  });

  test("isStale is true with a zero TTL", () => {
    const cache = new SloStatusCache(fakeCreds, 0);
    expect(cache.isStale).toBe(true);
  });
});

// ==== loadEnvFile ====
// * loads key=value pairs into process.env
// * does not override existing env vars
// * strips quotes from values
// * ignores comments and blank lines

describe("loadEnvFile", () => {
  function withTempEnv(content: string, fn: (dir: string) => void) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "caffeine-test-"));
    fs.writeFileSync(path.join(dir, ".env"), content);
    try {
      fn(dir);
    } finally {
      fs.rmSync(dir, { recursive: true });
    }
  }

  test("loads key=value pairs", () => {
    const key = `__CAFFEINE_TEST_${Date.now()}_A`;
    withTempEnv(`${key}=hello`, (dir) => {
      delete process.env[key];
      loadEnvFile(dir);
      expect(process.env[key]).toBe("hello");
      delete process.env[key];
    });
  });

  test("does not override existing env vars", () => {
    const key = `__CAFFEINE_TEST_${Date.now()}_B`;
    process.env[key] = "original";
    withTempEnv(`${key}=overwritten`, (dir) => {
      loadEnvFile(dir);
      expect(process.env[key]).toBe("original");
      delete process.env[key];
    });
  });

  test("strips double quotes from values", () => {
    const key = `__CAFFEINE_TEST_${Date.now()}_C`;
    withTempEnv(`${key}="quoted-value"`, (dir) => {
      delete process.env[key];
      loadEnvFile(dir);
      expect(process.env[key]).toBe("quoted-value");
      delete process.env[key];
    });
  });

  test("strips single quotes from values", () => {
    const key = `__CAFFEINE_TEST_${Date.now()}_D`;
    withTempEnv(`${key}='single-quoted'`, (dir) => {
      delete process.env[key];
      loadEnvFile(dir);
      expect(process.env[key]).toBe("single-quoted");
      delete process.env[key];
    });
  });

  test("ignores comments and blank lines", () => {
    const key = `__CAFFEINE_TEST_${Date.now()}_E`;
    withTempEnv(`# comment\n\n${key}=value\n# another comment`, (dir) => {
      delete process.env[key];
      loadEnvFile(dir);
      expect(process.env[key]).toBe("value");
      delete process.env[key];
    });
  });

  test("does nothing when .env file is missing", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "caffeine-test-noenv-"));
    try {
      loadEnvFile(dir); // should not throw
    } finally {
      fs.rmSync(dir, { recursive: true });
    }
  });
});
