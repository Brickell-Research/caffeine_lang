// TypeScript LSP server wrapping Gleam intelligence modules.
// Uses vscode-languageserver-node for protocol handling, delegates all
// language logic to the compiled Gleam modules.

import process from "node:process";

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
} from "npm:vscode-languageserver/node.js";
import { TextDocument } from "npm:vscode-languageserver-textdocument";

import { WorkspaceIndex } from "./lsp/workspace.ts";
import { registerHandlers } from "./lsp/handlers.ts";

// Prevent Deno from exiting when the event loop appears idle.
// vscode-languageserver reads stdin via Node.js streams, which Deno's
// compatibility layer may not treat as keeping the event loop alive.
setInterval(() => {}, 15_000);

// Ensure --stdio is in process.argv so vscode-languageserver detects stdio transport.
// Deno's compiled binary does not pass this flag through to process.argv.
if (!process.argv.includes("--stdio")) {
  process.argv.push("--stdio");
}

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const workspace = new WorkspaceIndex(documents);

registerHandlers({ connection, documents, workspace });
