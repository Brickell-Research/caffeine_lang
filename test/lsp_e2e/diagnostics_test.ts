/**
 * LSP e2e tests for diagnostics and cross-file validation.
 *
 * Covers single-file diagnostics, cross-file blueprint validation,
 * document changes, document close, and error recovery.
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

// ==== single_file_valid ====
// * Opens a valid blueprint file and verifies zero diagnostics
test("diagnostics: valid blueprint produces zero diagnostics", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_blueprint.caffeine");
    const text = await readFixture("valid_blueprint.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);

    const diag = await diagPromise;
    expect(diag.uri).toBe(uri);
    expect(diag.diagnostics.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== single_file_valid_expects ====
// * Opens a valid expects file and verifies diagnostics (may have cross-file warning)
test("diagnostics: valid expects file produces diagnostics response", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("valid_expects.caffeine");
    const text = await readFixture("valid_expects.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);

    const diag = await diagPromise;
    expect(diag.uri).toBe(uri);
    // Expects file references "test_blueprint" — without the blueprint file
    // being in the workspace, this may produce a "Blueprint not found" diagnostic
    expect(diag.diagnostics !== undefined).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== single_file_syntax_error ====
// * Opens a file with a syntax error and verifies diagnostic message
test("diagnostics: syntax error produces meaningful diagnostic", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("invalid_syntax.caffeine");
    const text = await readFixture("invalid_syntax.caffeine");

    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);

    const diag = await diagPromise;
    expect(diag.uri).toBe(uri);
    expect(diag.diagnostics.length > 0).toBeTruthy();

    // Verify the diagnostic has a meaningful message
    const firstDiag = diag.diagnostics[0];
    expect(firstDiag.message.length > 0).toBeTruthy();
    // Severity 1 = Error
    expect(firstDiag.severity).toBe(1);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== cross_file_blueprint_found ====
// * Opens a blueprint and an expects file, verifies no "blueprint not found" error
test("diagnostics: cross-file blueprint reference resolves when blueprint is open", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Open the blueprint file first so its names are indexed
    const bpUri = fixtureUri("valid_blueprint.caffeine");
    const bpText = await readFixture("valid_blueprint.caffeine");
    const bpDiagPromise = client.waitForDiagnostics(bpUri);
    client.openDocument(bpUri, bpText);
    await bpDiagPromise;

    // Now open the expects file that references "test_blueprint"
    const exUri = fixtureUri("valid_expects.caffeine");
    const exText = await readFixture("valid_expects.caffeine");
    const exDiagPromise = client.waitForDiagnostics(exUri);
    client.openDocument(exUri, exText);
    const exDiag = await exDiagPromise;

    // Should have no "blueprint not found" diagnostics since the blueprint is open
    const bpNotFoundDiags = exDiag.diagnostics.filter((d) =>
      d.message.includes("not found")
    );
    expect(bpNotFoundDiags.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== document_change_updates_diagnostics ====
// * Opens a file with errors, fixes the error, verifies diagnostics clear
test("diagnostics: document change updates diagnostics", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("invalid_syntax.caffeine");
    const invalidText = await readFixture("invalid_syntax.caffeine");

    // Open with invalid content — should produce diagnostics
    const diagPromise1 = client.waitForDiagnostics(uri);
    client.openDocument(uri, invalidText);
    const diag1 = await diagPromise1;
    expect(diag1.diagnostics.length > 0).toBeTruthy();

    // Change to valid content
    const validText = await readFixture("valid_blueprint.caffeine");
    const diagPromise2 = client.waitForDiagnostics(uri);
    client.changeDocument(uri, validText, 2);
    const diag2 = await diagPromise2;
    expect(diag2.diagnostics.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== document_close_clears_diagnostics ====
// * Opens a file with errors, closes it, verifies diagnostics are cleared
test("diagnostics: document close clears diagnostics", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = fixtureUri("invalid_syntax.caffeine");
    const text = await readFixture("invalid_syntax.caffeine");

    // Open with invalid content — wait for diagnostics
    const diagPromise1 = client.waitForDiagnostics(uri);
    client.openDocument(uri, text);
    const diag1 = await diagPromise1;
    expect(diag1.diagnostics.length > 0).toBeTruthy();

    // Close the document — server sends empty diagnostics
    const diagPromise2 = client.waitForDiagnostics(uri);
    client.closeDocument(uri);
    const diag2 = await diagPromise2;
    expect(diag2.diagnostics.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== error_recovery ====
// * Opens a file with syntax errors, fixes them incrementally, verifies diagnostics clear
test("diagnostics: error recovery clears diagnostics after fix", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    // Use a synthetic URI for a virtual document
    const uri = "file:///tmp/test_recovery.caffeine";

    // Start with broken content (missing colon after blueprint name)
    const broken = `Blueprints\n  * "test"\n    Requires { v: String }\n    Provides { v: "x" }\n`;
    const diagPromise1 = client.waitForDiagnostics(uri);
    client.openDocument(uri, broken);
    const diag1 = await diagPromise1;
    expect(diag1.diagnostics.length > 0).toBeTruthy();

    // Fix: add the missing colon
    const fixed = `Blueprints\n  * "test":\n    Requires { v: String }\n    Provides { v: "x" }\n`;
    const diagPromise2 = client.waitForDiagnostics(uri);
    client.changeDocument(uri, fixed, 2);
    const diag2 = await diagPromise2;
    expect(diag2.diagnostics.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== empty_document ====
// * Opens an empty document, verifies no diagnostics
test("diagnostics: empty document produces zero diagnostics", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const uri = "file:///tmp/test_empty.caffeine";
    const diagPromise = client.waitForDiagnostics(uri);
    client.openDocument(uri, "");
    const diag = await diagPromise;
    expect(diag.diagnostics.length).toBe(0);
  } finally {
    await client.shutdown();
  }
}, 30_000);
