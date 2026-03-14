/**
 * LSP e2e tests for formatting, semantic tokens, document symbols,
 * code actions, and references.
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
test("formatting fixes spacing in unformatted file", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const { uri, text } = await openFixture(client, "unformatted.caffeine");

    const edits = await client.formatting(uri);

    // Formatting should return at least one edit for the unformatted file
    expect(Array.isArray(edits) && edits.length > 0).toBeTruthy();

    // Each edit should have range and newText
    for (const edit of edits) {
      expect(edit.range).toBeTruthy();
      expect(typeof edit.newText === "string").toBeTruthy();
    }

    // The formatted result should differ from the original
    // (full-document replacement: range covers entire file, newText is the formatted version)
    const firstEdit = edits[0];
    expect(firstEdit.newText).not.toBe(text);
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== formatting_already_formatted ====
// * Sends formatting request on already-formatted file, verifies no meaningful change
test("formatting already-formatted file returns identity or no edits", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    const { uri, text } = await openFixture(
      client,
      "valid_measurement.caffeine",
    );

    const edits = await client.formatting(uri);

    if (edits && edits.length > 0) {
      // If edits are returned, they should be identity (newText equals original)
      const result = edits[0].newText;
      expect(result.trim()).toBe(text.trim());
    }
    // If no edits, that's also correct
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== semantic_tokens_returned ====
// * Requests semantic tokens for a measurement file, verifies data is returned
test("semantic tokens returns non-empty token data", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    await openFixture(client, "valid_measurement.caffeine");
    const uri = fixtureUri("valid_measurement.caffeine");

    const result = await client.semanticTokens(uri);

    expect(result).toBeTruthy();
    expect(Array.isArray(result.data)).toBeTruthy();
    expect(result.data.length > 0).toBeTruthy();

    // Data must be a multiple of 5 (each token is 5 integers)
    expect(result.data.length % 5).toBe(0);

    // Verify each group of 5 contains valid integers
    for (let i = 0; i < result.data.length; i += 5) {
      const deltaLine = result.data[i];
      const deltaStartChar = result.data[i + 1];
      const length = result.data[i + 2];
      const tokenType = result.data[i + 3];
      const tokenModifiers = result.data[i + 4];

      expect(deltaLine >= 0).toBeTruthy();
      expect(deltaStartChar >= 0).toBeTruthy();
      expect(length > 0).toBeTruthy();
      expect(tokenType >= 0 && tokenType <= 10).toBeTruthy();
      expect(tokenModifiers >= 0).toBeTruthy();
    }
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== document_symbols ====
// * Requests document symbols for a measurement file, verifies symbols are returned
test("document symbols returns symbols for measurement file", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    await openFixture(client, "valid_measurement.caffeine");
    const uri = fixtureUri("valid_measurement.caffeine");

    const symbols = await client.documentSymbols(uri);

    expect(Array.isArray(symbols)).toBeTruthy();
    expect(symbols.length > 0).toBeTruthy();

    // Verify symbol structure
    for (const symbol of symbols) {
      expect(
        typeof symbol.name === "string" && symbol.name.length > 0,
      ).toBeTruthy();
      expect(typeof symbol.kind === "number").toBeTruthy();
      expect(symbol.range).toBeTruthy();
      expect(symbol.selectionRange).toBeTruthy();
    }

    // Measurement items are top-level symbols with kind Class=5
    const classSymbol = symbols.find(
      (s: { kind: number }) => s.kind === 5,
    );
    expect(classSymbol).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== code_actions_quickfix ====
// * Opens a file with quoted field names, gets diagnostics, requests code actions
test("code actions returns quickfix for quoted field name", async () => {
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
    expect(diag.diagnostics.length > 0).toBeTruthy();

    // Find the quoted-field-name diagnostic
    const quotedDiag = diag.diagnostics.find(
      (d) => d.code === "quoted-field-name",
    );
    expect(quotedDiag).toBeTruthy();

    // Request code actions with the diagnostic
    const actions = await client.codeActions(uri, quotedDiag!.range, [
      quotedDiag!,
    ]);

    expect(Array.isArray(actions)).toBeTruthy();
    expect(actions.length > 0).toBeTruthy();

    // Verify quickfix structure
    const quickfix = actions[0];
    expect(quickfix.kind).toBe("quickfix");
    expect(quickfix.title.includes("Remove quotes")).toBeTruthy();
    expect(quickfix.edit).toBeTruthy();
    expect(quickfix.edit.changes).toBeTruthy();
  } finally {
    await client.shutdown();
  }
}, 30_000);

// ==== references_for_extendable ====
// * Opens a file with an extendable and its usage, verifies references are returned
test("references returns definition and usage for extendable", async () => {
  const client = new LspTestClient(ROOT_DIR);
  try {
    await client.start();
    await client.initialize();

    await openFixture(client, "with_extendable.caffeine");
    const uri = fixtureUri("with_extendable.caffeine");

    // Request references at the _defaults definition (line 0, character 0)
    const refs = await client.references(uri, 0, 1);

    expect(Array.isArray(refs)).toBeTruthy();
    expect(refs.length >= 2).toBeTruthy();

    // All references should be in the same file
    for (const ref of refs) {
      expect(ref.uri).toBe(uri);
      expect(ref.range).toBeTruthy();
    }
  } finally {
    await client.shutdown();
  }
}, 30_000);
