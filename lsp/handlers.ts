// LSP handler registration and lifecycle management — initialize, diagnostics,
// document close, watched files. Delegates feature requests to feature_handlers.

import fs from "node:fs";
import { fileURLToPath } from "node:url";
import {
  TextDocumentSyncKind,
  FileChangeType,
} from "npm:vscode-languageserver/node.js";
import type { Connection, TextDocuments } from "npm:vscode-languageserver/node.js";
import type { TextDocument } from "npm:vscode-languageserver-textdocument";

import {
  get_all_diagnostics,
  token_types,
  toList,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  gleamDiagToLsp,
} from "./helpers.ts";

import type { WorkspaceIndex } from "./workspace.ts";

import {
  handleHover,
  handleCompletion,
  handleHighlight,
  handleFormatting,
  handleCodeAction,
  handlePrepareRename,
  handleRename,
  handleDocumentSymbol,
  handleSemanticTokens,
  handleFoldingRanges,
  handleSelectionRanges,
  handleLinkedEditing,
} from "./document_features.ts";

import {
  handleDefinition,
  handleReferences,
  handleWorkspaceSymbol,
} from "./navigation_features.ts";

import {
  handleTypeHierarchyPrepare,
  handleTypeHierarchySupertypes,
  handleTypeHierarchySubtypes,
} from "./type_hierarchy_features.ts";

export interface HandlerContext {
  connection: Connection;
  documents: TextDocuments<TextDocument>;
  workspace: WorkspaceIndex;
}

interface DiagnosticScheduler {
  scheduleRevalidation: () => void;
}

// --- Entry point ---

export function registerHandlers(ctx: HandlerContext): void {
  const scheduler = createDiagnosticScheduler(ctx);

  registerInitializeHandler(ctx);
  registerDiagnosticsHandler(ctx, scheduler);
  registerDocumentCloseHandler(ctx, scheduler);
  registerWatchedFilesHandler(ctx, scheduler);

  ctx.connection.onHover((p) => handleHover(ctx, p));
  ctx.connection.onCompletion((p) => handleCompletion(ctx, p));
  ctx.connection.onDefinition((p) => handleDefinition(ctx, p));
  ctx.connection.onDeclaration((p) => handleDefinition(ctx, p));
  ctx.connection.onDocumentHighlight((p) => handleHighlight(ctx, p));
  ctx.connection.onReferences((p) => handleReferences(ctx, p));
  ctx.connection.onDocumentFormatting((p) => handleFormatting(ctx, p));
  ctx.connection.onCodeAction((p) => handleCodeAction(ctx, p));
  ctx.connection.onPrepareRename((p) => handlePrepareRename(ctx, p));
  ctx.connection.onRenameRequest((p) => handleRename(ctx, p));
  ctx.connection.onDocumentSymbol((p) => handleDocumentSymbol(ctx, p));
  ctx.connection.languages.semanticTokens.on((p) => handleSemanticTokens(ctx, p));
  ctx.connection.onFoldingRanges((p) => handleFoldingRanges(ctx, p));
  ctx.connection.onSelectionRanges((p) => handleSelectionRanges(ctx, p));
  ctx.connection.languages.onLinkedEditingRange((p) => handleLinkedEditing(ctx, p));
  ctx.connection.languages.typeHierarchy.onPrepare((p) => handleTypeHierarchyPrepare(ctx, p));
  ctx.connection.languages.typeHierarchy.onSupertypes((p) => handleTypeHierarchySupertypes(ctx, p));
  ctx.connection.languages.typeHierarchy.onSubtypes((p) => handleTypeHierarchySubtypes(ctx, p));
  ctx.connection.onWorkspaceSymbol((p) => handleWorkspaceSymbol(ctx, p));

  ctx.documents.listen(ctx.connection);
  ctx.connection.listen();
}

// --- Diagnostic scheduling ---

function createDiagnosticScheduler(ctx: HandlerContext): DiagnosticScheduler {
  const { connection, documents, workspace } = ctx;
  let revalidateTimer: ReturnType<typeof setTimeout> | null = null;

  function revalidateAll() {
    const knownBlueprints = toList(workspace.allKnownBlueprints());
    const knownExpectations = toList(workspace.allKnownExpectationIdentifiers());
    for (const doc of documents.all()) {
      try {
        const allDiags = gleamArray(
          get_all_diagnostics(doc.getText(), knownBlueprints, knownExpectations) as GleamList,
        );
        connection.sendDiagnostics({
          uri: doc.uri,
          diagnostics: allDiags.map(gleamDiagToLsp),
        });
      } catch { /* ignore */ }
    }
  }

  return {
    scheduleRevalidation() {
      if (revalidateTimer) clearTimeout(revalidateTimer);
      revalidateTimer = setTimeout(() => {
        revalidateTimer = null;
        revalidateAll();
      }, 50);
    },
  };
}

// --- Initialize ---

function registerInitializeHandler(ctx: HandlerContext): void {
  const { connection, workspace } = ctx;

  // deno-lint-ignore no-explicit-any
  connection.onInitialize(async (params: any) => {
    const rootUri: string | undefined = params.rootUri ?? params.rootPath;
    if (rootUri) {
      try {
        await workspace.initializeFromRoot(rootUri);
      } catch { /* ignore */ }
    }

    return {
      capabilities: {
        textDocumentSync: TextDocumentSyncKind.Full,
        hoverProvider: true,
        definitionProvider: true,
        declarationProvider: true,
        documentHighlightProvider: true,
        referencesProvider: true,
        renameProvider: { prepareProvider: true },
        foldingRangeProvider: true,
        selectionRangeProvider: true,
        linkedEditingRangeProvider: true,
        documentFormattingProvider: true,
        documentSymbolProvider: true,
        workspaceSymbolProvider: true,
        typeHierarchyProvider: true,
        completionProvider: {
          triggerCharacters: [":", "[", "{", ",", "\""],
        },
        codeActionProvider: {
          codeActionKinds: ["quickfix"],
        },
        semanticTokensProvider: {
          legend: {
            tokenTypes: gleamArray(token_types as GleamList),
            tokenModifiers: [],
          },
          full: true,
        },
      },
      serverInfo: { name: "caffeine-lsp", version: "0.1.0" },
    };
  });
}

// --- Diagnostics on change ---

function registerDiagnosticsHandler(
  ctx: HandlerContext,
  scheduler: DiagnosticScheduler,
): void {
  const { connection, documents, workspace } = ctx;
  const diagnosticTimers = new Map<string, ReturnType<typeof setTimeout>>();

  documents.onDidChangeContent((change) => {
    const uri = change.document.uri;

    const existing = diagnosticTimers.get(uri);
    if (existing) clearTimeout(existing);

    diagnosticTimers.set(
      uri,
      setTimeout(() => {
        diagnosticTimers.delete(uri);
        const doc = documents.get(uri);
        if (!doc) return;
        const text = doc.getText();

        if (workspace.updateIndicesForFile(uri, text)) {
          scheduler.scheduleRevalidation();
        } else {
          try {
            const allDiags = gleamArray(
              get_all_diagnostics(
                text,
                toList(workspace.allKnownBlueprints()),
                toList(workspace.allKnownExpectationIdentifiers()),
              ) as GleamList,
            );
            connection.sendDiagnostics({
              uri,
              diagnostics: allDiags.map(gleamDiagToLsp),
            });
          } catch {
            connection.sendDiagnostics({ uri, diagnostics: [] });
          }
        }
      }, 300),
    );
  });
}

// --- Document close ---

function registerDocumentCloseHandler(
  ctx: HandlerContext,
  scheduler: DiagnosticScheduler,
): void {
  const { connection, workspace } = ctx;

  ctx.documents.onDidClose((event) => {
    const uri = event.document.uri;
    connection.sendDiagnostics({ uri, diagnostics: [] });

    const hadBlueprintsBefore = workspace.blueprintIndex.has(uri);
    const hadExpectationsBefore = workspace.expectationIndex.has(uri);

    (async () => {
      let diskText: string | null = null;
      try {
        diskText = await fs.promises.readFile(fileURLToPath(uri), "utf-8");
      } catch { /* File may have been deleted */ }

      if (diskText) {
        workspace.updateIndicesForFile(uri, diskText);
      } else {
        workspace.blueprintIndex.delete(uri);
        workspace.expectationIndex.delete(uri);
      }

      const hasBlueprintsAfter = workspace.blueprintIndex.has(uri);
      const hasExpectationsAfter = workspace.expectationIndex.has(uri);
      if (hadBlueprintsBefore || hasBlueprintsAfter || hadExpectationsBefore || hasExpectationsAfter) {
        scheduler.scheduleRevalidation();
      }
    })().catch(() => { /* async close handler — errors are non-fatal */ });
  });
}

// --- Watched files ---

function registerWatchedFilesHandler(
  ctx: HandlerContext,
  scheduler: DiagnosticScheduler,
): void {
  ctx.connection.onDidChangeWatchedFiles(async (params) => {
    let indicesChanged = false;
    for (const change of params.changes) {
      if (!change.uri.endsWith(".caffeine")) continue;
      if (await processWatchedFileChange(ctx.workspace, change)) {
        indicesChanged = true;
      }
    }
    if (indicesChanged) scheduler.scheduleRevalidation();
  });
}

// deno-lint-ignore no-explicit-any
async function processWatchedFileChange(workspace: WorkspaceIndex, change: any): Promise<boolean> {
  const uri = change.uri;
  if (change.type === FileChangeType.Deleted) {
    workspace.files.delete(uri);
    const hadBlueprints = workspace.blueprintIndex.delete(uri);
    const hadExpectations = workspace.expectationIndex.delete(uri);
    return hadBlueprints || hadExpectations;
  }
  workspace.files.add(uri);
  const text = await workspace.getFileContentAsync(uri);
  return text ? workspace.updateIndicesForFile(uri, text) : false;
}
