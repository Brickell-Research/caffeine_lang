// LSP handler registration and lifecycle management — initialize, diagnostics,
// document close, watched files. Delegates feature requests to feature_handlers.

import fs from "node:fs";
import { fileURLToPath } from "node:url";
import {
  TextDocumentSyncKind,
  FileChangeType,
} from "vscode-languageserver/node.js";
import type { Connection, TextDocuments } from "vscode-languageserver/node.js";
import type { TextDocument } from "vscode-languageserver-textdocument";

import {
  get_all_diagnostics,
  get_dead_measurement_diagnostics,
  get_linker_diagnostics,
  token_types,
  toList,
  version,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  gleamDiagToLsp,
} from "./helpers.ts";

import type { WorkspaceIndex } from "./workspace.ts";
import { debug } from "./debug.ts";
import { loadEnvFile, getDatadogCredentials } from "./vendors/types.ts";
import { SloStatusCache } from "./vendors/slo_cache.ts";

import {
  handleHover,
  handleCompletion,
  handleSignatureHelp,
  handleInlayHints,
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
  handleCodeLens,
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
  sloCache: SloStatusCache | null;
}

interface DiagnosticScheduler {
  scheduleRevalidation: () => void;
}

/** Debounce delay for per-document diagnostics after edits (ms). */
const DIAGNOSTIC_DEBOUNCE_MS = 300;

/** Delay before cross-file revalidation after index changes (ms). */
const REVALIDATION_DELAY_MS = 50;

// --- Entry point ---

export function registerHandlers(ctx: HandlerContext): void {
  const scheduler = createDiagnosticScheduler(ctx);

  registerInitializeHandler(ctx);
  registerDiagnosticsHandler(ctx, scheduler);
  registerDocumentCloseHandler(ctx, scheduler);
  registerWatchedFilesHandler(ctx, scheduler);

  ctx.connection.onHover((p) => handleHover(ctx, p));
  ctx.connection.onCompletion((p) => handleCompletion(ctx, p));
  ctx.connection.onSignatureHelp((p) => handleSignatureHelp(ctx, p));
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
  ctx.connection.languages.inlayHint.on((p) => handleInlayHints(ctx, p));
  ctx.connection.languages.typeHierarchy.onPrepare((p) => handleTypeHierarchyPrepare(ctx, p));
  ctx.connection.languages.typeHierarchy.onSupertypes((p) => handleTypeHierarchySupertypes(ctx, p));
  ctx.connection.languages.typeHierarchy.onSubtypes((p) => handleTypeHierarchySubtypes(ctx, p));
  ctx.connection.onWorkspaceSymbol((p) => handleWorkspaceSymbol(ctx, p));
  ctx.connection.onCodeLens((p) => handleCodeLens(ctx, p, ctx.sloCache));

  ctx.documents.listen(ctx.connection);
  ctx.connection.listen();
}

// --- Diagnostic scheduling ---

function createDiagnosticScheduler(ctx: HandlerContext): DiagnosticScheduler {
  const { connection, documents, workspace } = ctx;
  let revalidateTimer: ReturnType<typeof setTimeout> | null = null;

  function revalidateAll() {
    debug(`revalidateAll: ${documents.all().length} open documents`);
    const knownMeasurements = toList(workspace.allKnownMeasurements());
    const knownExpectations = toList(workspace.allKnownExpectationIdentifiers());
    const referencedMeasurements = toList(workspace.allReferencedMeasurements());
    const validatedMeasurements = workspace.allValidatedMeasurements();
    for (const doc of documents.all()) {
      try {
        const text = doc.getText();
        const frontendDiags = gleamArray(
          get_all_diagnostics(text, knownMeasurements, knownExpectations) as GleamList,
        );
        const linkerDiags = gleamArray(
          get_linker_diagnostics(text, validatedMeasurements) as GleamList,
        );
        const deadMeasurementDiags = gleamArray(
          get_dead_measurement_diagnostics(text, referencedMeasurements) as GleamList,
        );
        connection.sendDiagnostics({
          uri: doc.uri,
          diagnostics: [...frontendDiags, ...linkerDiags, ...deadMeasurementDiags].map(gleamDiagToLsp),
        });
      } catch (e) { debug(`revalidateAll(${doc.uri}): ${e}`); }
    }
  }

  return {
    scheduleRevalidation() {
      if (revalidateTimer) clearTimeout(revalidateTimer);
      revalidateTimer = setTimeout(() => {
        revalidateTimer = null;
        revalidateAll();
      }, REVALIDATION_DELAY_MS);
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
      debug(`initialize: root=${rootUri}`);

      // Load .env from workspace root (overrides existing env vars)
      const rootPath = rootUri.startsWith("file://")
        ? fileURLToPath(rootUri)
        : rootUri;
      loadEnvFile(rootPath);

      // Create or update the SLO cache with credentials from the (now-loaded) env.
      // This handles the case where VS Code was launched with stale/missing credentials
      // but the workspace .env has the correct ones.
      const creds = getDatadogCredentials();
      if (creds) {
        if (ctx.sloCache) {
          debug("slo-overlay: updating credentials from .env");
          ctx.sloCache.updateCredentials(creds);
        } else {
          debug("slo-overlay: Datadog credentials found via .env");
          ctx.sloCache = new SloStatusCache(creds);
          ctx.sloCache.onDidRefresh(() => {
            debug("slo-overlay: cache refreshed, requesting codeLens refresh from client");
            connection.sendRequest("workspace/codeLens/refresh")
              .then(() => debug("slo-overlay: codeLens refresh succeeded"))
              .catch((e: unknown) => debug(`slo-overlay: codeLens refresh rejected: ${e}`));
          });
        }
      }

      try {
        await workspace.initializeFromRoot(rootUri);
        debug(`initialize: indexed ${workspace.files.size} files, ${workspace.measurementIndex.size} measurement files, ${workspace.expectationIndex.size} expectation files`);
        // Kick off SLO data fetch if Datadog expectations exist
        if (ctx.sloCache && workspace.hasVendor("datadog")) {
          debug("slo-overlay: Datadog expectations found, fetching SLO data");
          ctx.sloCache.refresh();
          ctx.sloCache.startPeriodicRefresh();
        }
      } catch (e) { debug(`initialize: ${e}`); }
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
        signatureHelpProvider: {
          triggerCharacters: [":"],
          retriggerCharacters: [","],
        },
        inlayHintProvider: true,
        codeLensProvider: { resolveProvider: false },
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
      serverInfo: { name: "caffeine-lsp", version: version as string },
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
            const frontendDiags = gleamArray(
              get_all_diagnostics(
                text,
                toList(workspace.allKnownMeasurements()),
                toList(workspace.allKnownExpectationIdentifiers()),
              ) as GleamList,
            );
            const linkerDiags = gleamArray(
              get_linker_diagnostics(
                text,
                workspace.allValidatedMeasurements(),
              ) as GleamList,
            );
            const deadMeasurementDiags = gleamArray(
              get_dead_measurement_diagnostics(
                text,
                toList(workspace.allReferencedMeasurements()),
              ) as GleamList,
            );
            connection.sendDiagnostics({
              uri,
              diagnostics: [...frontendDiags, ...linkerDiags, ...deadMeasurementDiags].map(gleamDiagToLsp),
            });
          } catch (e) {
            debug(`diagnostics(${uri}): ${e}`);
            connection.sendDiagnostics({ uri, diagnostics: [] });
          }
        }
      }, DIAGNOSTIC_DEBOUNCE_MS),
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

    const hadMeasurementsBefore = workspace.measurementIndex.has(uri);
    const hadExpectationsBefore = workspace.expectationIndex.has(uri);

    (async () => {
      let diskText: string | null = null;
      try {
        diskText = await fs.promises.readFile(fileURLToPath(uri), "utf-8");
      } catch { /* File may have been deleted — expected */ }

      if (diskText) {
        workspace.updateIndicesForFile(uri, diskText);
      } else {
        workspace.removeFile(uri);
      }

      const hasMeasurementsAfter = workspace.measurementIndex.has(uri);
      const hasExpectationsAfter = workspace.expectationIndex.has(uri);
      if (hadMeasurementsBefore || hasMeasurementsAfter || hadExpectationsBefore || hasExpectationsAfter) {
        scheduler.scheduleRevalidation();
      }
    })().catch((e) => { debug(`documentClose: ${e}`); });
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
    return workspace.removeFile(uri);
  }
  workspace.files.add(uri);
  const text = await workspace.getFileContentAsync(uri);
  return text ? workspace.updateIndicesForFile(uri, text) : false;
}
