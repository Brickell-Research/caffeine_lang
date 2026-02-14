/**
 * LSP e2e tests for diagnostics and cross-file validation.
 *
 * Covers single-file diagnostics, cross-file blueprint validation,
 * document changes, document close, and error recovery.
 */

import { assertEquals, assert } from "jsr:@std/assert";
import { LspTestClient, withTimeout } from "./client.ts";

const ROOT_DIR = new URL("../../", import.meta.url).pathname.replace(
  /\/$/,
  "",
);

function fixtureUri(name: string): string {
  return `file://${ROOT_DIR}/test/lsp_e2e/fixtures/${name}`;
}

async function readFixture(name: string): Promise<string> {
  return await Deno.readTextFile(
    `${ROOT_DIR}/test/lsp_e2e/fixtures/${name}`,
  );
}

// ==== single_file_valid ====
// * Opens a valid blueprint file and verifies zero diagnostics
Deno.test({
  name: "diagnostics: valid blueprint produces zero diagnostics",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const uri = fixtureUri("valid_blueprint.caffeine");
      const text = await readFixture("valid_blueprint.caffeine");

      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, text);

      const diag = await diagPromise;
      assertEquals(diag.uri, uri);
      assertEquals(
        diag.diagnostics.length,
        0,
        "valid blueprint should have zero diagnostics",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== single_file_valid_expects ====
// * Opens a valid expects file and verifies diagnostics (may have cross-file warning)
Deno.test({
  name: "diagnostics: valid expects file produces diagnostics response",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const uri = fixtureUri("valid_expects.caffeine");
      const text = await readFixture("valid_expects.caffeine");

      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, text);

      const diag = await diagPromise;
      assertEquals(diag.uri, uri);
      // Expects file references "test_blueprint" — without the blueprint file
      // being in the workspace, this may produce a "Blueprint not found" diagnostic
      assert(
        diag.diagnostics !== undefined,
        "should receive a diagnostics array",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== single_file_syntax_error ====
// * Opens a file with a syntax error and verifies diagnostic message
Deno.test({
  name: "diagnostics: syntax error produces meaningful diagnostic",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const uri = fixtureUri("invalid_syntax.caffeine");
      const text = await readFixture("invalid_syntax.caffeine");

      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, text);

      const diag = await diagPromise;
      assertEquals(diag.uri, uri);
      assert(
        diag.diagnostics.length > 0,
        "syntax error should produce at least one diagnostic",
      );

      // Verify the diagnostic has a meaningful message
      const firstDiag = diag.diagnostics[0];
      assert(
        firstDiag.message.length > 0,
        "diagnostic should have a non-empty message",
      );
      // Severity 1 = Error
      assertEquals(firstDiag.severity, 1, "syntax errors should be severity Error");
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== cross_file_blueprint_found ====
// * Opens a blueprint and an expects file, verifies no "blueprint not found" error
Deno.test({
  name: "diagnostics: cross-file blueprint reference resolves when blueprint is open",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
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
      assertEquals(
        bpNotFoundDiags.length,
        0,
        "should not have 'blueprint not found' errors when blueprint is open",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== document_change_updates_diagnostics ====
// * Opens a file with errors, fixes the error, verifies diagnostics clear
Deno.test({
  name: "diagnostics: document change updates diagnostics",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
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
      assert(
        diag1.diagnostics.length > 0,
        "invalid content should produce diagnostics",
      );

      // Change to valid content
      const validText = await readFixture("valid_blueprint.caffeine");
      const diagPromise2 = client.waitForDiagnostics(uri);
      client.changeDocument(uri, validText, 2);
      const diag2 = await diagPromise2;
      assertEquals(
        diag2.diagnostics.length,
        0,
        "fixing the error should clear diagnostics",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== document_close_clears_diagnostics ====
// * Opens a file with errors, closes it, verifies diagnostics are cleared
Deno.test({
  name: "diagnostics: document close clears diagnostics",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
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
      assert(
        diag1.diagnostics.length > 0,
        "invalid content should produce diagnostics",
      );

      // Close the document — server sends empty diagnostics
      const diagPromise2 = client.waitForDiagnostics(uri);
      client.closeDocument(uri);
      const diag2 = await diagPromise2;
      assertEquals(
        diag2.diagnostics.length,
        0,
        "closing a document should clear its diagnostics",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== error_recovery ====
// * Opens a file with syntax errors, fixes them incrementally, verifies diagnostics clear
Deno.test({
  name: "diagnostics: error recovery clears diagnostics after fix",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      // Use a synthetic URI for a virtual document
      const uri = "file:///tmp/test_recovery.caffeine";

      // Start with broken content (missing colon after blueprint name)
      const broken = `Blueprints for "SLO"\n  * "test"\n    Requires { v: String }\n    Provides { v: "x" }\n`;
      const diagPromise1 = client.waitForDiagnostics(uri);
      client.openDocument(uri, broken);
      const diag1 = await diagPromise1;
      assert(
        diag1.diagnostics.length > 0,
        "broken content should produce diagnostics",
      );

      // Fix: add the missing colon
      const fixed = `Blueprints for "SLO"\n  * "test":\n    Requires { v: String }\n    Provides { v: "x" }\n`;
      const diagPromise2 = client.waitForDiagnostics(uri);
      client.changeDocument(uri, fixed, 2);
      const diag2 = await diagPromise2;
      assertEquals(
        diag2.diagnostics.length,
        0,
        "fixed content should have zero diagnostics",
      );
    } finally {
      await client.shutdown();
    }
  }),
});

// ==== empty_document ====
// * Opens an empty document, verifies no diagnostics
Deno.test({
  name: "diagnostics: empty document produces zero diagnostics",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const uri = "file:///tmp/test_empty.caffeine";
      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, "");
      const diag = await diagPromise;
      assertEquals(
        diag.diagnostics.length,
        0,
        "empty document should have zero diagnostics",
      );
    } finally {
      await client.shutdown();
    }
  }),
});
