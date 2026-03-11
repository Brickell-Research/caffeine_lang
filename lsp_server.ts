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

// SLO cache is created lazily — either from env vars at startup,
// or after loading .env from workspace root during initialization.
const ddCredentials = getDatadogCredentials();
let sloCache: SloStatusCache | null = null;
if (ddCredentials) {
  debug("slo-overlay: Datadog credentials found in environment");
  sloCache = new SloStatusCache(ddCredentials);
  sloCache.onDidRefresh(() => {
    debug("slo-overlay: cache refreshed, requesting codeLens refresh from client");
    connection.sendRequest("workspace/codeLens/refresh")
      .then(() => debug("slo-overlay: codeLens refresh succeeded"))
      .catch((e: unknown) => debug(`slo-overlay: codeLens refresh rejected: ${e}`));
  });
}

const ctx = { connection, documents, workspace, sloCache };
registerHandlers(ctx);
