// TypeScript LSP server wrapping Gleam intelligence modules.
// Uses vscode-languageserver-node for protocol handling, delegates all
// language logic to the compiled Gleam modules.

import process from "node:process";

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
} from "vscode-languageserver/node.js";
import { TextDocument } from "vscode-languageserver-textdocument";

import { WorkspaceIndex } from "./lsp/workspace.ts";
import { registerHandlers } from "./lsp/handlers.ts";
import { getDatadogCredentials } from "./lsp/vendors/types.ts";
import { SloStatusCache } from "./lsp/vendors/slo_cache.ts";
import { debug } from "./lsp/debug.ts";

// Ensure --stdio is in process.argv so vscode-languageserver detects stdio transport.
if (!process.argv.includes("--stdio")) {
  process.argv.push("--stdio");
}

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const workspace = new WorkspaceIndex(documents);

// Initialize SLO overlay if Datadog credentials are available.
const ddCredentials = getDatadogCredentials();
let sloCache: SloStatusCache | null = null;
if (ddCredentials) {
  debug("slo-overlay: Datadog credentials found");
  sloCache = new SloStatusCache(ddCredentials);
  // Notify IDE to refresh code lenses after SLO data loads.
  sloCache.onDidRefresh(() => {
    connection.languages.codeLens.refresh();
  });
} else {
  debug("slo-overlay: disabled (no DD_API_KEY/DD_APP_KEY)");
}

registerHandlers({ connection, documents, workspace, sloCache });
