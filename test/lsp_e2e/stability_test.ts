/**
 * LSP e2e tests for server stability.
 *
 * Verifies the server survives after workspace scanning completes,
 * especially with malformed documents. Regression test for the Deno
 * event-loop exit bug where the server would die after async I/O
 * from scanning 100+ .caffeine files settled.
 */

import { assert } from "jsr:@std/assert";
import { LspTestClient, withTimeout } from "./client.ts";

const ROOT_DIR = new URL("../../", import.meta.url).pathname.replace(
  /\/$/,
  "",
);

function fixtureUri(name: string): string {
  return `file://${ROOT_DIR}/test/lsp_e2e/fixtures/${name}`;
}

// ==== server_survives_workspace_scan ====
// * Initializes with real workspace root (100+ .caffeine files)
// * Opens a malformed document that triggers parsing errors
// * Waits for workspace scan to fully complete
// * Verifies server is still responsive after idle period
Deno.test({
  name: "stability: server survives after workspace scan with malformed document",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      // This is the exact content from the user's crash report — a malformed
      // Blueprints file with unterminated strings in a signals block.
      const malformedContent = `Blueprints for "SLO"
  * "Uptime":
    Requires { }
    Provides {
      signals: {
        "
        "
      }
    }
`;

      const uri = fixtureUri("crash_malformed.caffeine");
      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, malformedContent);
      await diagPromise;

      // Wait for workspace scan to settle — the bug triggers when all async
      // operations (scanning .caffeine files, building indices) complete and
      // Deno's event loop becomes idle.
      await new Promise((r) => setTimeout(r, 3000));

      // Server must still respond to requests after the idle period.
      const hover = await client.hover(uri, 0, 0);
      // We don't assert hover content — just that the server responded.
      assert(hover !== undefined, "server should still respond after idle period");
    } finally {
      await client.shutdown();
    }
  }, 20_000),
});

// ==== server_survives_multiple_documents ====
// * Opens multiple documents and verifies server stays alive through
//   sustained activity after the watchdog interval
// * Uses request/response (not notifications) to verify liveness,
//   avoiding CI timing sensitivity with diagnostic notifications
Deno.test({
  name: "stability: server handles multiple document operations after workspace scan",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const validContent = `Blueprints for "TestStability"
  * "Check":
    Requires { }
    Provides {
      slo_type: "monitor"
    }
`;

      const uri1 = fixtureUri("stability_a.caffeine");
      const uri2 = fixtureUri("stability_b.caffeine");

      // Open first document
      client.openDocument(uri1, validContent);

      // Wait past the 3-second watchdog interval
      await new Promise((r) => setTimeout(r, 4000));

      // Verify server is still alive via request/response
      const hover1 = await client.hover(uri1, 0, 0);
      assert(hover1 !== undefined, "server should respond after idle");

      // Open second document — server must not have exited
      client.openDocument(uri2, validContent);

      // Modify first document
      client.changeDocument(uri1, validContent + "\n", 2);

      // Verify server handled both documents
      const symbols = await client.documentSymbols(uri1);
      assert(Array.isArray(symbols), "should return symbols array");
    } finally {
      await client.shutdown();
    }
  }, 20_000),
});

// ==== production_entrypoint_survives ====
// * Launches via main.mjs lsp (same as compiled binary)
// * Verifies the production entrypoint doesn't crash after idle
// * Regression test: deno compile must include --allow-run for the
//   vscode-languageserver parent-process watchdog
Deno.test({
  name: "stability: production entrypoint (main.mjs) survives after workspace scan",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: withTimeout(async () => {
    const client = new LspTestClient(ROOT_DIR, "production");
    try {
      await client.start();
      await client.initialize();

      const uri = fixtureUri("stability_prod.caffeine");
      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, `Blueprints for "ProdTest"\n  * "Item":\n    Requires { }\n    Provides { slo_type: "monitor" }\n`);
      await diagPromise;

      // Wait past the 3-second watchdog interval
      await new Promise((r) => setTimeout(r, 4000));

      // Server must still be alive
      const hover = await client.hover(uri, 0, 0);
      assert(hover !== undefined, "production entrypoint should survive watchdog check");
    } finally {
      await client.shutdown();
    }
  }, 20_000),
});
