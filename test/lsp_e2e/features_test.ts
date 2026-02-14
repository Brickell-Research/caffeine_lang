/**
 * LSP e2e feature tests.
 *
 * Validates hover, completion, and go-to-definition features.
 */

import { assertEquals, assert } from "jsr:@std/assert";
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

// ==== hover_on_type_keyword ====
// * Hover over "String" type keyword returns markdown with type description
Deno.test({
  name: "hover on type keyword returns markdown content",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assert(result !== null, "hover should return a result for type keyword");
      assert(result.contents, "hover result should have contents");
      assertEquals(result.contents.kind, "markdown");
      assert(
        result.contents.value.includes("String"),
        "hover content should mention String",
      );
    } finally {
      await client.shutdown();
    }
  },
});

// ==== hover_on_field_name ====
// * Hover over "vendor" field name returns content
Deno.test({
  name: "hover on field name returns content",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assert(result !== null, "hover should return a result for field name");
      assert(result.contents, "hover result should have contents");
      assertEquals(result.contents.kind, "markdown");
      assert(
        result.contents.value.includes("vendor"),
        "hover content should mention the field name",
      );
    } finally {
      await client.shutdown();
    }
  },
});

// ==== hover_on_empty_space ====
// * Hover on whitespace returns null
Deno.test({
  name: "hover on whitespace returns null",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assertEquals(result, null, "hover on whitespace should return null");
    } finally {
      await client.shutdown();
    }
  },
});

// ==== completion_type_keywords ====
// * Completion after ":" in Requires block returns type keywords
Deno.test({
  name: "completion in Requires block returns type keywords",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assert(Array.isArray(items), "completion should return an array");
      assert(items.length > 0, "completion should return items");

      const labels = items.map((item: Record<string, unknown>) => item.label);
      assert(labels.includes("String"), "should include String type");
      assert(labels.includes("Integer"), "should include Integer type");
      assert(labels.includes("Float"), "should include Float type");
      assert(labels.includes("Boolean"), "should include Boolean type");
    } finally {
      await client.shutdown();
    }
  },
});

// ==== completion_blueprint_names ====
// * Completion at "for" position suggests blueprint names from workspace
Deno.test({
  name: "completion suggests blueprint names from workspace",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assert(Array.isArray(items), "completion should return an array");
      assert(items.length > 0, "should return at least one blueprint name");

      const labels = items.map((item: Record<string, unknown>) => item.label);
      assert(
        labels.includes("test_blueprint"),
        "should include 'test_blueprint' blueprint from workspace",
      );
    } finally {
      await client.shutdown();
    }
  },
});

// ==== goto_definition_extendable ====
// * Go-to-definition on extendable reference navigates to its definition
Deno.test({
  name: "go-to-definition on extendable navigates to definition",
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
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

      assert(result !== null, "definition should return a location");
      assertEquals(result.uri, uri, "definition should be in the same file");
      assertEquals(
        result.range.start.line,
        0,
        "definition should point to line 0 where _defaults is defined",
      );
      assertEquals(
        result.range.start.character,
        0,
        "definition should start at character 0",
      );
    } finally {
      await client.shutdown();
    }
  },
});
