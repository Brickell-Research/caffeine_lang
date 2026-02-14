/**
 * LSP e2e tests for formatting, semantic tokens, document symbols,
 * code actions, and references.
 */

import {
  assertEquals,
  assert,
  assertNotEquals,
} from "jsr:@std/assert";
import { LspTestClient } from "./client.ts";

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

/** Helper: start a client, initialize, open a document, wait for diagnostics. */
async function openFixture(
  client: LspTestClient,
  fixtureName: string,
): Promise<{ uri: string; text: string }> {
  const uri = fixtureUri(fixtureName);
  const text = await readFixture(fixtureName);
  const diagPromise = client.waitForDiagnostics(uri);
  client.openDocument(uri, text);
  await diagPromise;
  return { uri, text };
}

// ==== formatting_fixes_spacing ====
// * Sends formatting request on unformatted file, verifies edits are returned
Deno.test({
  name: "formatting fixes spacing in unformatted file",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const { uri, text } = await openFixture(client, "unformatted.caffeine");

      const edits = await client.formatting(uri);

      // Formatting should return at least one edit for the unformatted file
      assert(
        Array.isArray(edits) && edits.length > 0,
        "formatting should return edits for unformatted file",
      );

      // Each edit should have range and newText
      for (const edit of edits) {
        assert(edit.range, "edit should have a range");
        assert(typeof edit.newText === "string", "edit should have newText");
      }

      // The formatted result should differ from the original
      // (full-document replacement: range covers entire file, newText is the formatted version)
      const firstEdit = edits[0];
      assertNotEquals(
        firstEdit.newText,
        text,
        "formatted text should differ from original",
      );
    } finally {
      await client.shutdown();
    }
  },
});

// ==== formatting_already_formatted ====
// * Sends formatting request on already-formatted file, verifies no meaningful change
Deno.test({
  name: "formatting already-formatted file returns identity or no edits",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const { uri, text } = await openFixture(
        client,
        "valid_blueprint.caffeine",
      );

      const edits = await client.formatting(uri);

      if (edits && edits.length > 0) {
        // If edits are returned, they should be identity (newText equals original)
        const result = edits[0].newText;
        assertEquals(
          result.trim(),
          text.trim(),
          "formatted text should match original for already-formatted file",
        );
      }
      // If no edits, that's also correct
    } finally {
      await client.shutdown();
    }
  },
});

// ==== semantic_tokens_returned ====
// * Requests semantic tokens for a blueprint file, verifies data is returned
Deno.test({
  name: "semantic tokens returns non-empty token data",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      await openFixture(client, "valid_blueprint.caffeine");
      const uri = fixtureUri("valid_blueprint.caffeine");

      const result = await client.semanticTokens(uri);

      assert(result, "semantic tokens result should not be null");
      assert(Array.isArray(result.data), "result should have data array");
      assert(result.data.length > 0, "data array should be non-empty");

      // Data must be a multiple of 5 (each token is 5 integers)
      assertEquals(
        result.data.length % 5,
        0,
        "data length should be a multiple of 5",
      );

      // Verify each group of 5 contains valid integers
      for (let i = 0; i < result.data.length; i += 5) {
        const deltaLine = result.data[i];
        const deltaStartChar = result.data[i + 1];
        const length = result.data[i + 2];
        const tokenType = result.data[i + 3];
        const tokenModifiers = result.data[i + 4];

        assert(deltaLine >= 0, `deltaLine should be >= 0 at index ${i}`);
        assert(
          deltaStartChar >= 0,
          `deltaStartChar should be >= 0 at index ${i}`,
        );
        assert(length > 0, `length should be > 0 at index ${i}`);
        assert(
          tokenType >= 0 && tokenType <= 10,
          `tokenType should be 0-10 at index ${i}, got ${tokenType}`,
        );
        assert(
          tokenModifiers >= 0,
          `tokenModifiers should be >= 0 at index ${i}`,
        );
      }
    } finally {
      await client.shutdown();
    }
  },
});

// ==== document_symbols ====
// * Requests document symbols for a blueprint file, verifies symbols are returned
Deno.test({
  name: "document symbols returns symbols for blueprint file",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      await openFixture(client, "valid_blueprint.caffeine");
      const uri = fixtureUri("valid_blueprint.caffeine");

      const symbols = await client.documentSymbols(uri);

      assert(Array.isArray(symbols), "symbols should be an array");
      assert(symbols.length > 0, "should return at least one symbol");

      // Verify symbol structure
      for (const symbol of symbols) {
        assert(
          typeof symbol.name === "string" && symbol.name.length > 0,
          "symbol should have a non-empty name",
        );
        assert(typeof symbol.kind === "number", "symbol should have a kind");
        assert(symbol.range, "symbol should have a range");
        assert(symbol.selectionRange, "symbol should have a selectionRange");
      }

      // Look for the blueprint block symbol (Blueprints for "SLO" -> kind Module=2)
      const moduleSymbol = symbols.find(
        (s: { kind: number }) => s.kind === 2,
      );
      assert(moduleSymbol, "should have a module symbol for the blueprint block");
    } finally {
      await client.shutdown();
    }
  },
});

// ==== code_actions_quickfix ====
// * Opens a file with quoted field names, gets diagnostics, requests code actions
Deno.test({
  name: "code actions returns quickfix for quoted field name",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      const uri = fixtureUri("quoted_field.caffeine");
      const text = await readFixture("quoted_field.caffeine");

      const diagPromise = client.waitForDiagnostics(uri);
      client.openDocument(uri, text);
      const diag = await diagPromise;

      // Should have at least one diagnostic for the quoted field name
      assert(
        diag.diagnostics.length > 0,
        "should have diagnostics for quoted field name",
      );

      // Find the quoted-field-name diagnostic
      const quotedDiag = diag.diagnostics.find(
        (d) => d.code === "quoted-field-name",
      );
      assert(quotedDiag, "should have a quoted-field-name diagnostic");

      // Request code actions with the diagnostic
      const actions = await client.codeActions(uri, quotedDiag!.range, [
        quotedDiag!,
      ]);

      assert(Array.isArray(actions), "actions should be an array");
      assert(actions.length > 0, "should return at least one code action");

      // Verify quickfix structure
      const quickfix = actions[0];
      assertEquals(quickfix.kind, "quickfix", "action kind should be quickfix");
      assert(
        quickfix.title.includes("Remove quotes"),
        "action title should mention removing quotes",
      );
      assert(quickfix.edit, "quickfix should have an edit");
      assert(
        quickfix.edit.changes,
        "quickfix edit should have changes",
      );
    } finally {
      await client.shutdown();
    }
  },
});

// ==== references_for_extendable ====
// * Opens a file with an extendable and its usage, verifies references are returned
Deno.test({
  name: "references returns definition and usage for extendable",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    const client = new LspTestClient(ROOT_DIR);
    try {
      await client.start();
      await client.initialize();

      await openFixture(client, "with_extendable.caffeine");
      const uri = fixtureUri("with_extendable.caffeine");

      // Request references at the _defaults definition (line 0, character 0)
      const refs = await client.references(uri, 0, 1);

      assert(Array.isArray(refs), "refs should be an array");
      assert(
        refs.length >= 2,
        `should find at least 2 references (definition + usage), got ${refs.length}`,
      );

      // All references should be in the same file
      for (const ref of refs) {
        assertEquals(ref.uri, uri, "reference should be in the same file");
        assert(ref.range, "reference should have a range");
      }
    } finally {
      await client.shutdown();
    }
  },
});
