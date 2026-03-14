/**
 * LSP e2e feature tests.
 *
 * Validates hover, completion, and go-to-definition features.
 */

import { expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { LspTestClient } from "./client.ts";

const ROOT_DIR = new URL("../../", import.meta.url).pathname.replace(
  /\/$/,
  "",
);

function fixtureUri(name: string): string {
  return `file://${ROOT_DIR}/test/lsp_e2e/fixtures/${name}`;
}

async function readFixture(name: string): Promise<string> {
  return await readFile(
    `${ROOT_DIR}/test/lsp_e2e/fixtures/${name}`,
    "utf-8",
  );
}

// ==== hover_on_type_keyword ====
// * Hover over "String" type keyword returns markdown with type description
test("hover on type keyword returns markdown content", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_measurement.caffeine");
    const text = await readFixture("valid_measurement.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 1: "  Requires { env: String, status: Boolean }"
    // "String" starts at character 18
    const result = await client.hover(uri, 1, 18);

    expect(result !== null).toBeTruthy();
    expect(result.contents).toBeTruthy();
    expect(result.contents.kind).toBe("markdown");
    expect(result.contents.value.includes("String")).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== hover_on_field_name ====
// * Hover over "indicators" field name returns content
test("hover on field name returns content", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_measurement.caffeine");
    const text = await readFixture("valid_measurement.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 3: '    indicators: { good: "query_good", total: "query_total" },'
    // "indicators" starts at character 4 (in Provides block)
    const result = await client.hover(uri, 3, 4);

    expect(result !== null).toBeTruthy();
    expect(result.contents).toBeTruthy();
    expect(result.contents.kind).toBe("markdown");
    expect(result.contents.value.includes("indicators")).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== hover_on_empty_space ====
// * Hover on whitespace returns null
test("hover on whitespace returns null", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_measurement.caffeine");
    const text = await readFixture("valid_measurement.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 1, character 0 is leading whitespace
    const result = await client.hover(uri, 1, 0);

    expect(result).toBeNull();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== completion_type_keywords ====
// * Completion after ":" in Requires block returns type keywords
test("completion in Requires block returns type keywords", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_measurement.caffeine");
    const text = await readFixture("valid_measurement.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 1: "  Requires { env: String, status: Boolean }"
    // Character 17 is the space after ":", should trigger type completions
    const items = await client.completion(uri, 1, 17);

    expect(Array.isArray(items)).toBeTruthy();
    expect(items.length > 0).toBeTruthy();

    const labels = items.map((item: Record<string, unknown>) => item.label);
    expect(labels.includes("String")).toBeTruthy();
    expect(labels.includes("Integer")).toBeTruthy();
    expect(labels.includes("Float")).toBeTruthy();
    expect(labels.includes("Boolean")).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== completion_measurement_names ====
// * Completion at "measured by" position suggests measurement names from workspace
test("completion suggests measurement names from workspace", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Open the measurement file so the server indexes it
    const bpUri = fixtureUri("valid_measurement.caffeine");
    const bpText = await readFixture("valid_measurement.caffeine");
    const bpDiagPromise = client.waitForDiagnostics(bpUri);
    client.openDocument(bpUri, bpText);
    await bpDiagPromise;

    // Open the expects file
    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    await exDiagPromise;

    // Line 0: 'Expectations measured by "test_measurement"'
    // Character 26 is right after the opening quote — triggers measurement name completions
    const items = await client.completion(exUri, 0, 26);

    expect(Array.isArray(items)).toBeTruthy();
    expect(items.length > 0).toBeTruthy();

    const labels = items.map((item: Record<string, unknown>) => item.label);
    expect(labels.includes("test_measurement")).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== goto_definition_extendable ====
// * Go-to-definition on extendable reference navigates to its definition
test("go-to-definition on extendable navigates to definition", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("with_extendable.caffeine");
    const text = await readFixture("with_extendable.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 3: '  * "checkout" extends [_defaults]:'
    // "_defaults" starts at character 24
    const result = await client.definition(uri, 3, 24);

    expect(result !== null).toBeTruthy();
    expect(result[0].uri).toBe(uri);
    expect(result[0].range.start.line).toBe(0);
    expect(result[0].range.start.character).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== signature_help ====
// * Signature help inside expectation Provides block returns measurement params
test("signature help returns measurement parameters in expects Provides", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Open measurement first so server indexes it
    const bpUri = fixtureUri("valid_measurement.caffeine");
    const bpText = await readFixture("valid_measurement.caffeine");
    const bpDiagPromise = client.waitForDiagnostics(bpUri);
    client.openDocument(bpUri, bpText);
    await bpDiagPromise;

    // Open expects file
    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    await exDiagPromise;

    // Line 3: '      env: "production",'
    // Cursor on "env" field line
    const result = await client.signatureHelp(exUri, 3, 10);

    expect(result !== null).toBeTruthy();
    expect(result.signatures.length).toBeGreaterThan(0);
    expect(result.signatures[0].label).toContain("test_measurement");
    expect(result.signatures[0].parameters.length).toBeGreaterThan(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== inlay_hints ====
// * Inlay hints in expects file show field types from measurement
test("inlay hints show field types from measurement", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Open measurement first
    const bpUri = fixtureUri("valid_measurement.caffeine");
    const bpText = await readFixture("valid_measurement.caffeine");
    const bpDiagPromise = client.waitForDiagnostics(bpUri);
    client.openDocument(bpUri, bpText);
    await bpDiagPromise;

    // Open expects file
    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    await exDiagPromise;

    // Request inlay hints for the full file range
    const hints = await client.inlayHints(exUri, 0, 10);

    expect(Array.isArray(hints)).toBeTruthy();
    expect(hints.length).toBeGreaterThan(0);
    // At least one hint should contain a type string
    const labels = hints.map((h: Record<string, unknown>) => h.label);
    const hasTypeHint = labels.some((l: unknown) =>
      typeof l === "string" && (l.includes("String") || l.includes("Float")),
    );
    expect(hasTypeHint).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== type_hierarchy_prepare ====
// * Type hierarchy prepare on expectation item returns hierarchy items
test("type hierarchy prepare on expectation item returns items", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    await exDiagPromise;

    // Line 1: '  * "test_expectation":'
    // Cursor on "test_expectation" (inside the item name)
    const result = await client.prepareTypeHierarchy(exUri, 1, 8);

    expect(result !== null).toBeTruthy();
    expect(Array.isArray(result)).toBeTruthy();
    if (result && result.length > 0) {
      expect(result[0].name).toBe("test_expectation");
    }
  } finally {
    await client.shutdown();
  }
}, 30_000);
