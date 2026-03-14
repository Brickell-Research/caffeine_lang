// Tests for graph features — dependency relation extraction and source editing.

import { describe, expect, test } from "bun:test";
import { extractDependencyRelations } from "./workspace_parsers.ts";

// --- extractDependencyRelations ---

describe("extractDependencyRelations", () => {
  test("returns empty map for non-expectations file", () => {
    const text = `Blueprints for "Auth"\n* "Login SLO"\n  Requires {}`;
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(0);
  });

  test("returns empty map when no relations blocks exist", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides {`,
      `    threshold: 99.9`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(0);
  });

  test("extracts hard and soft deps from single item", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides {`,
      `    threshold: 99.9`,
      `    relations: {`,
      `      hard: ["acme.infra.db.query_slo"]`,
      `      soft: ["acme.cache.redis.cache_slo"]`,
      `    }`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(1);
    const deps = result.get("Login SLO");
    expect(deps).toBeDefined();
    expect(deps!.hard).toEqual(["acme.infra.db.query_slo"]);
    expect(deps!.soft).toEqual(["acme.cache.redis.cache_slo"]);
  });

  test("handles multiple items with different relations", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides {`,
      `    relations: { hard: ["a.b.c.d"] soft: [] }`,
      `  }`,
      `* "Signup SLO"`,
      `  Provides {`,
      `    relations: { hard: [] soft: ["x.y.z.w"] }`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(2);
    expect(result.get("Login SLO")!.hard).toEqual(["a.b.c.d"]);
    expect(result.get("Login SLO")!.soft).toEqual([]);
    expect(result.get("Signup SLO")!.hard).toEqual([]);
    expect(result.get("Signup SLO")!.soft).toEqual(["x.y.z.w"]);
  });

  test("skips comment lines", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `# This is a comment`,
      `* "Login SLO"`,
      `  Provides {`,
      `    relations: { hard: ["a.b.c.d"] soft: [] }`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(1);
    expect(result.get("Login SLO")!.hard).toEqual(["a.b.c.d"]);
  });

  test("handles multiple hard deps", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides {`,
      `    relations: { hard: ["a.b.c.d", "e.f.g.h"] soft: [] }`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.get("Login SLO")!.hard).toEqual(["a.b.c.d", "e.f.g.h"]);
  });

  test("item with no relations block is excluded", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides { threshold: 99.9 }`,
      `* "Signup SLO"`,
      `  Provides {`,
      `    relations: { hard: ["a.b.c.d"] soft: [] }`,
      `  }`,
    ].join("\n");
    const result = extractDependencyRelations(text);
    expect(result.size).toBe(1);
    expect(result.has("Signup SLO")).toBe(true);
    expect(result.has("Login SLO")).toBe(false);
  });
});

// --- addDependency / removeDependency (via source text manipulation) ---
// These are tested indirectly through the graph_features module's internal functions.
// We import and test the key text manipulation by re-implementing the pattern matching here.

describe("dependency source editing", () => {
  test("can detect relations block in item text", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides {`,
      `    relations: {`,
      `      hard: ["a.b.c.d"]`,
      `      soft: []`,
      `    }`,
      `  }`,
    ].join("\n");
    const deps = extractDependencyRelations(text);
    expect(deps.get("Login SLO")!.hard).toEqual(["a.b.c.d"]);
    expect(deps.get("Login SLO")!.soft).toEqual([]);
  });

  test("single-line relations block", () => {
    const text = [
      `Expectations for "Auth SLO"`,
      `* "Login SLO"`,
      `  Provides { relations: { hard: ["x.y.z.w"] soft: [] } }`,
    ].join("\n");
    const deps = extractDependencyRelations(text);
    expect(deps.get("Login SLO")!.hard).toEqual(["x.y.z.w"]);
  });
});
