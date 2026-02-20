// LSP handler registrations — all connection.on* and documents.on* callbacks.

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
  get_hover,
  get_completions,
  get_semantic_tokens,
  token_types,
  get_symbols,
  get_definition,
  get_blueprint_ref_at_position,
  get_relation_ref_with_range_at_position,
  get_code_actions,
  ActionDiagnostic,
  QuotedFieldName,
  BlueprintNotFound,
  DependencyNotFound,
  NoDiagnosticCode,
  format,
  get_highlights,
  get_references,
  get_blueprint_name_at,
  find_references_to_name,
  prepare_rename,
  get_rename_edits,
  get_folding_ranges,
  get_selection_range,
  get_linked_editing_ranges,
  get_workspace_symbols,
  prepare_type_hierarchy,
  BlueprintKind,
  Ok,
  toList,
  Some,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  range,
  gleamDiagToLsp,
  gleamSymbolToLsp,
  gleamSelectionRangeToLsp,
} from "./helpers.ts";

import type { WorkspaceIndex } from "./workspace.ts";

interface HandlerContext {
  connection: Connection;
  documents: TextDocuments<TextDocument>;
  workspace: WorkspaceIndex;
}

/** Shared diagnostic scheduling state used across handler groups. */
interface DiagnosticScheduler {
  revalidateAll: () => void;
  scheduleRevalidation: () => void;
}

export function registerHandlers(ctx: HandlerContext): void {
  const scheduler = createDiagnosticScheduler(ctx);

  registerInitializeHandler(ctx);
  registerDiagnosticsHandlers(ctx, scheduler);
  registerNavigationHandlers(ctx);
  registerEditHandlers(ctx);
  registerStructureHandlers(ctx);
  registerWorkspaceHandlers(ctx, scheduler);

  ctx.documents.listen(ctx.connection);
  ctx.connection.listen();
}

// --- Diagnostic Scheduling ---

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
      } catch {
        /* ignore */
      }
    }
  }

  function scheduleRevalidation() {
    if (revalidateTimer) clearTimeout(revalidateTimer);
    revalidateTimer = setTimeout(() => {
      revalidateTimer = null;
      revalidateAll();
    }, 50);
  }

  return { revalidateAll, scheduleRevalidation };
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
      serverInfo: {
        name: "caffeine-lsp",
        version: "0.1.0",
      },
    };
  });
}

// --- Diagnostics ---

function registerDiagnosticsHandlers(
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

  documents.onDidClose((event) => {
    const uri = event.document.uri;
    connection.sendDiagnostics({ uri, diagnostics: [] });

    const hadBlueprintsBefore = workspace.blueprintIndex.has(uri);
    const hadExpectationsBefore = workspace.expectationIndex.has(uri);

    (async () => {
      let diskText: string | null = null;
      try {
        diskText = await fs.promises.readFile(fileURLToPath(uri), "utf-8");
      } catch {
        // File may have been deleted
      }

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

// --- Navigation (hover, completion, definition, highlights, references) ---

function registerNavigationHandlers(ctx: HandlerContext): void {
  const { connection, documents, workspace } = ctx;

  connection.onHover((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    try {
      const result = get_hover(
        doc.getText(),
        params.position.line,
        params.position.character,
      );
      if (result instanceof Some) {
        return {
          contents: { kind: "markdown" as const, value: result[0] },
        };
      }
    } catch { /* ignore */ }
    return null;
  });

  connection.onCompletion((params) => {
    const doc = documents.get(params.textDocument.uri);
    const text = doc ? doc.getText() : "";

    try {
      const blueprintNames = toList(workspace.allKnownBlueprints());
      const items = gleamArray(
        get_completions(text, params.position.line, params.position.character, blueprintNames) as GleamList,
      );
      return items.map((item) => ({
        label: item.label,
        kind: item.kind,
        detail: item.detail,
      }));
    } catch {
      return [];
    }
  });

  // deno-lint-ignore no-explicit-any
  async function resolveDefinitionOrDeclaration(params: any) {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    const text = doc.getText();

    try {
      const result = get_definition(
        text,
        params.position.line,
        params.position.character,
      );
      if (result instanceof Some) {
        const [defLine, defCol, nameLen] = [result[0][0], result[0][1], result[0][2]];
        return {
          uri: params.textDocument.uri,
          range: range(defLine, defCol, defLine, defCol + nameLen),
        };
      }

      const bpRef = get_blueprint_ref_at_position(
        text,
        params.position.line,
        params.position.character,
      );
      if (bpRef instanceof Some) {
        const target = await workspace.findCrossFileBlueprintDef(bpRef[0] as string);
        if (target) {
          return {
            uri: target.uri,
            range: range(target.line, target.col, target.line, target.col + target.nameLen),
          };
        }
      }

      const relRefWithRange = get_relation_ref_with_range_at_position(
        text,
        params.position.line,
        params.position.character,
      );
      if (relRefWithRange instanceof Some) {
        const refStr = relRefWithRange[0][0] as string;
        const refStartCol = relRefWithRange[0][1] as number;
        const refLen = refStr.length;
        const target = await workspace.findExpectationByIdentifier(refStr);
        if (target) {
          const srcLine = params.position.line;
          return [{
            originSelectionRange: range(srcLine, refStartCol, srcLine, refStartCol + refLen),
            targetUri: target.uri,
            targetRange: range(target.line, target.col, target.line, target.col + target.nameLen),
            targetSelectionRange: range(target.line, target.col, target.line, target.col + target.nameLen),
          }];
        }
      }
    } catch { /* ignore */ }
    return null;
  }

  connection.onDefinition(resolveDefinitionOrDeclaration);
  connection.onDeclaration(resolveDefinitionOrDeclaration);

  connection.onDocumentHighlight((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    try {
      const highlights = gleamArray(
        get_highlights(doc.getText(), params.position.line, params.position.character) as GleamList,
      );
      return highlights.map((h) => ({
        range: range(h[0], h[1], h[0], h[1] + h[2]),
        kind: 1, // Text
      }));
    } catch {
      return [];
    }
  });

  connection.onReferences(async (params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    try {
      const text = doc.getText();
      const line = params.position.line;
      const char = params.position.character;

      const sameFileRefs = gleamArray(
        get_references(text, line, char) as GleamList,
      ).map((r) => ({
        uri: params.textDocument.uri,
        range: range(r[0], r[1], r[0], r[1] + r[2]),
      }));

      const blueprintName = get_blueprint_name_at(text, line, char) as string;
      if (!blueprintName) return sameFileRefs;

      const crossFileRefs: typeof sameFileRefs = [];
      const searched = new Set<string>([params.textDocument.uri]);
      for (const uri of workspace.files) {
        if (searched.has(uri)) continue;
        searched.add(uri);
        const otherText = await workspace.getFileContentAsync(uri);
        if (!otherText) continue;
        try {
          const otherRefs = gleamArray(
            find_references_to_name(otherText, blueprintName) as GleamList,
          );
          for (const r of otherRefs) {
            crossFileRefs.push({
              uri,
              range: range(r[0], r[1], r[0], r[1] + r[2]),
            });
          }
        } catch { /* skip files that fail */ }
      }

      return [...sameFileRefs, ...crossFileRefs];
    } catch {
      return [];
    }
  });
}

// --- Editing (formatting, code actions, rename) ---

function registerEditHandlers(ctx: HandlerContext): void {
  const { connection, documents } = ctx;

  connection.onDocumentFormatting((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    const text = doc.getText();
    try {
      const result = format(text);
      if (result instanceof Ok) {
        const lineCount = text.split("\n").length;
        return [
          {
            range: range(0, 0, lineCount, 0),
            newText: result[0],
          },
        ];
      }
    } catch { /* ignore */ }
    return [];
  });

  connection.onCodeAction((params) => {
    const uri = params.textDocument.uri;

    try {
      const gleamDiags = toList(
        params.context.diagnostics.map(
          (d) =>
            new ActionDiagnostic(
              d.range.start.line,
              d.range.start.character,
              d.range.end.line,
              d.range.end.character,
              d.message,
              d.code === "quoted-field-name" ? new QuotedFieldName()
                : d.code === "blueprint-not-found" ? new BlueprintNotFound()
                : d.code === "dependency-not-found" ? new DependencyNotFound()
                : new NoDiagnosticCode(),
            ),
        ),
      );

      const actions = gleamArray(get_code_actions(gleamDiags, uri) as GleamList);
      return actions.map((action) => {
        const diag = action.diagnostic;
        return {
          title: action.title,
          kind: action.kind,
          isPreferred: action.is_preferred,
          diagnostics: [
            {
              message: diag.message,
              source: "caffeine",
              range: range(diag.line, diag.character, diag.end_line, diag.end_character),
            },
          ],
          edit: {
            changes: {
              [action.uri]: gleamArray(action.edits as GleamList).map((e) => ({
                range: range(e.start_line, e.start_character, e.end_line, e.end_character),
                newText: e.new_text,
              })),
            },
          },
        };
      });
    } catch {
      return [];
    }
  });

  connection.onPrepareRename((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    try {
      const result = prepare_rename(
        doc.getText(),
        params.position.line,
        params.position.character,
      );
      if (result instanceof Some) {
        const [rLine, rCol, rLen] = [result[0][0], result[0][1], result[0][2]];
        return {
          range: range(rLine, rCol, rLine, rCol + rLen),
          placeholder: doc.getText().substring(
            doc.offsetAt({ line: rLine, character: rCol }),
            doc.offsetAt({ line: rLine, character: rCol + rLen }),
          ),
        };
      }
    } catch { /* ignore */ }
    return null;
  });

  // deno-lint-ignore no-explicit-any
  connection.onRenameRequest((params: any) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    try {
      const edits = gleamArray(
        get_rename_edits(doc.getText(), params.position.line, params.position.character) as GleamList,
      );
      if (edits.length === 0) return null;
      return {
        changes: {
          [params.textDocument.uri]: edits.map((e) => ({
            range: range(e[0], e[1], e[0], e[1] + e[2]),
            newText: params.newName,
          })),
        },
      };
    } catch {
      return null;
    }
  });
}

// --- Structure (symbols, tokens, folding, selection, linked editing, type hierarchy) ---

function registerStructureHandlers(ctx: HandlerContext): void {
  const { connection, documents, workspace } = ctx;

  connection.onDocumentSymbol((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    try {
      const symbols = gleamArray(get_symbols(doc.getText()) as GleamList);
      return symbols.map(gleamSymbolToLsp);
    } catch {
      return [];
    }
  });

  connection.languages.semanticTokens.on((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return { data: [] };

    try {
      const data = gleamArray(get_semantic_tokens(doc.getText()) as GleamList);
      return { data };
    } catch {
      return { data: [] };
    }
  });

  connection.onFoldingRanges((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    try {
      const ranges = gleamArray(get_folding_ranges(doc.getText()) as GleamList);
      return ranges.map((r) => ({
        startLine: r.start_line,
        endLine: r.end_line,
        kind: "region" as const,
      }));
    } catch {
      return [];
    }
  });

  connection.onSelectionRanges((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return [];

    try {
      return params.positions.map((pos) => {
        const sr = get_selection_range(doc.getText(), pos.line, pos.character);
        return gleamSelectionRangeToLsp(sr);
      });
    } catch {
      return [];
    }
  });

  connection.languages.onLinkedEditingRange((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    try {
      const ranges = gleamArray(
        get_linked_editing_ranges(doc.getText(), params.position.line, params.position.character) as GleamList,
      );
      if (ranges.length === 0) return null;
      return {
        ranges: ranges.map((r) => range(r[0], r[1], r[0], r[1] + r[2])),
      };
    } catch {
      return null;
    }
  });

  connection.languages.typeHierarchy.onPrepare((params) => {
    const doc = documents.get(params.textDocument.uri);
    if (!doc) return null;

    try {
      const items = gleamArray(
        prepare_type_hierarchy(
          doc.getText(),
          params.position.line,
          params.position.character,
        ) as GleamList,
      );
      if (items.length === 0) return null;
      return items.map((item) => {
        const r = range(item.line, item.col, item.line, item.col + item.name_len);
        return {
          name: item.name,
          kind: 5, // SymbolKind.Class
          uri: params.textDocument.uri,
          range: r,
          selectionRange: r,
          data: {
            kind: item.kind instanceof BlueprintKind ? "blueprint" : "expectation",
            blueprint: item.blueprint,
          },
        };
      });
    } catch {
      return null;
    }
  });

  // deno-lint-ignore no-explicit-any
  connection.languages.typeHierarchy.onSupertypes(async (params: any) => {
    const data = params.item?.data;
    if (!data || data.kind !== "expectation" || !data.blueprint) return [];

    // deno-lint-ignore no-explicit-any
    const results: any[] = [];
    for (const uri of workspace.files) {
      const text = await workspace.getFileContentAsync(uri);
      if (!text || !text.trimStart().startsWith("Blueprints")) continue;
      if (!text.includes(`"${data.blueprint}"`)) continue;

      try {
        const symbols = gleamArray(get_workspace_symbols(text) as GleamList);
        for (const sym of symbols) {
          if (sym.name === data.blueprint && sym.kind === 5) {
            const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
            results.push({
              name: sym.name,
              kind: 5,
              uri,
              range: r,
              selectionRange: r,
              data: { kind: "blueprint", blueprint: "" },
            });
          }
        }
      } catch { /* ignore */ }
    }

    return results;
  });

  // deno-lint-ignore no-explicit-any
  connection.languages.typeHierarchy.onSubtypes(async (params: any) => {
    const data = params.item?.data;
    if (!data || data.kind !== "blueprint") return [];

    const blueprintName = params.item.name;
    // deno-lint-ignore no-explicit-any
    const results: any[] = [];

    for (const uri of workspace.files) {
      const text = await workspace.getFileContentAsync(uri);
      if (!text || !text.trimStart().startsWith("Expectations")) continue;
      if (!text.includes(`"${blueprintName}"`)) continue;

      try {
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
          const match = lines[i].match(/^\s*\*\s+"([^"]+)"/);
          if (!match) continue;
          const itemName = match[1];
          const items = gleamArray(
            prepare_type_hierarchy(text, i, lines[i].indexOf(itemName)) as GleamList,
          );
          for (const item of items) {
            if (item.blueprint === blueprintName) {
              const r = range(item.line, item.col, item.line, item.col + item.name_len);
              results.push({
                name: item.name,
                kind: 5,
                uri,
                range: r,
                selectionRange: r,
                data: { kind: "expectation", blueprint: blueprintName },
              });
            }
          }
        }
      } catch { /* ignore */ }
    }

    return results;
  });
}

// --- Workspace (workspace symbols, watched files) ---

function registerWorkspaceHandlers(
  ctx: HandlerContext,
  scheduler: DiagnosticScheduler,
): void {
  const { connection, workspace } = ctx;

  // deno-lint-ignore no-explicit-any
  connection.onWorkspaceSymbol(async (params: any) => {
    const query = (params.query ?? "").toLowerCase();
    // deno-lint-ignore no-explicit-any
    const results: any[] = [];

    for (const uri of workspace.files) {
      const text = await workspace.getFileContentAsync(uri);
      if (!text) continue;

      try {
        const symbols = gleamArray(get_workspace_symbols(text) as GleamList);
        for (const sym of symbols) {
          if (query && !(sym.name as string).toLowerCase().includes(query)) continue;
          const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
          results.push({
            name: sym.name,
            kind: sym.kind,
            location: { uri, range: r },
          });
        }
      } catch { /* ignore */ }
    }

    return results;
  });

  connection.onDidChangeWatchedFiles(async (params) => {
    let indicesChanged = false;
    for (const change of params.changes) {
      const uri = change.uri;
      if (!uri.endsWith(".caffeine")) continue;

      if (change.type === FileChangeType.Deleted) {
        workspace.files.delete(uri);
        if (workspace.blueprintIndex.has(uri)) {
          workspace.blueprintIndex.delete(uri);
          indicesChanged = true;
        }
        if (workspace.expectationIndex.has(uri)) {
          workspace.expectationIndex.delete(uri);
          indicesChanged = true;
        }
      } else {
        workspace.files.add(uri);
        const text = await workspace.getFileContentAsync(uri);
        if (text && workspace.updateIndicesForFile(uri, text)) {
          indicesChanged = true;
        }
      }
    }

    if (indicesChanged) {
      scheduler.scheduleRevalidation();
    }
  });
}
