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

    const uri = fixtureUri("valid_blueprint.caffeine");
    const text = await readFixture("valid_blueprint.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 2: "    Requires { vendor: String, threshold: Float }"
    // "String" starts at character 23
    const result = await client.hover(uri, 2, 23);

    expect(result !== null).toBeTruthy();
    expect(result.contents).toBeTruthy();
    expect(result.contents.kind).toBe("markdown");
    expect(result.contents.value.includes("String")).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== hover_on_field_name ====
// * Hover over "vendor" field name returns content
test("hover on field name returns content", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_blueprint.caffeine");
    const text = await readFixture("valid_blueprint.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 3: "    Provides { vendor: "datadog", threshold: 99.9 }"
    // "vendor" starts at character 15
    const result = await client.hover(uri, 3, 15);

    expect(result !== null).toBeTruthy();
    expect(result.contents).toBeTruthy();
    expect(result.contents.kind).toBe("markdown");
    expect(result.contents.value.includes("vendor")).toBeTruthy();
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

    const uri = fixtureUri("valid_blueprint.caffeine");
    const text = await readFixture("valid_blueprint.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 2, character 0 is leading whitespace
    const result = await client.hover(uri, 2, 0);

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

    const uri = fixtureUri("valid_blueprint.caffeine");
    const text = await readFixture("valid_blueprint.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    await diagPromise;

    // Line 2: "    Requires { vendor: String, threshold: Float }"
    // Character 22 is the space after ":", should trigger type completions
    const items = await client.completion(uri, 2, 22);

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

// ==== completion_blueprint_names ====
// * Completion at "for" position suggests blueprint names from workspace
test("completion suggests blueprint names from workspace", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Open the blueprint file so the server indexes it
    const bpUri = fixtureUri("valid_blueprint.caffeine");
    const bpText = await readFixture("valid_blueprint.caffeine");
    const bpDiagPromise = client.waitForDiagnostics(bpUri);
    client.openDocument(bpUri, bpText);
    await bpDiagPromise;

    // Open the expects file
    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    await exDiagPromise;

    // Line 0: 'Expectations for "test_blueprint"'
    // Character 18 is right after the opening quote — triggers blueprint name completions
    const items = await client.completion(exUri, 0, 18);

    expect(Array.isArray(items)).toBeTruthy();
    expect(items.length > 0).toBeTruthy();

    const labels = items.map((item: Record<string, unknown>) => item.label);
    expect(labels.includes("test_blueprint")).toBeTruthy();
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
    expect(result.uri).toBe(uri);
    expect(result.range.start.line).toBe(0);
    expect(result.range.start.character).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);
