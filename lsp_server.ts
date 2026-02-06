// TypeScript LSP server wrapping Gleam intelligence modules.
// Uses vscode-languageserver-node for protocol handling, delegates all
// language logic to the compiled Gleam modules.

import process from "node:process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  TextDocumentSyncKind,
  DiagnosticSeverity,
  FileChangeType,
} from "npm:vscode-languageserver/node.js";
import { TextDocument } from "npm:vscode-languageserver-textdocument";

// Ensure --stdio is in process.argv so vscode-languageserver detects stdio transport.
// Deno's compiled binary may not pass this flag through to process.argv.
if (!process.argv.includes("--stdio")) {
  process.argv.push("--stdio");
}

// Gleam-compiled intelligence modules
import { get_diagnostics, get_cross_file_diagnostics, diagnostic_code_to_string, QuotedFieldName, BlueprintNotFound, NoDiagnosticCode } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/diagnostics.mjs";
import { get_hover } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/hover.mjs";
import { get_completions } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/completion.mjs";
import {
  get_semantic_tokens,
  token_types,
} from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/semantic_tokens.mjs";
import { get_symbols } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/document_symbols.mjs";
import { get_definition, get_blueprint_ref_at_position } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/definition.mjs";
import { get_code_actions, ActionDiagnostic } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/code_actions.mjs";
import { format } from "./caffeine_lsp/build/dev/javascript/caffeine_lang/caffeine_lang/frontend/formatter.mjs";
import { get_highlights } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/highlight.mjs";
import { get_references, get_blueprint_name_at, find_references_to_name } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/references.mjs";
import { prepare_rename, get_rename_edits } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/rename.mjs";
import { get_folding_ranges } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/folding_range.mjs";
import { get_selection_range } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/selection_range.mjs";
import { get_linked_editing_ranges } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/linked_editing_range.mjs";
import { get_workspace_symbols } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/workspace_symbols.mjs";
import { prepare_type_hierarchy, BlueprintKind } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/type_hierarchy.mjs";

// Gleam runtime types
import { Ok, toList } from "./caffeine_lsp/build/dev/javascript/prelude.mjs";
import { Some } from "./caffeine_lsp/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

// deno-lint-ignore no-explicit-any
type GleamList = { toArray(): any[] };

// --- Helpers ---

/** Convert a GleamList to a plain JS array. */
// deno-lint-ignore no-explicit-any
function gleamArray(gl: GleamList): any[] {
  return gl.toArray();
}

/** Build an LSP Range from line/col positions. */
function range(
  startLine: number,
  startChar: number,
  endLine: number,
  endChar: number,
) {
  return {
    start: { line: startLine, character: startChar },
    end: { line: endLine, character: endChar },
  };
}

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

// Workspace file tracking for workspace/symbol
let workspaceRoot: string | null = null;
const workspaceFiles = new Set<string>();

/** Recursively find all .caffeine files under a directory. */
function scanCaffeineFiles(dir: string): void {
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      scanCaffeineFiles(full);
    } else if (entry.isFile() && entry.name.endsWith(".caffeine")) {
      workspaceFiles.add(pathToFileURL(full).toString());
    }
  }
}

/** Read file content: prefer open document, fall back to disk. */
function getFileContent(uri: string): string | null {
  const doc = documents.get(uri);
  if (doc) return doc.getText();
  try {
    const filePath = fileURLToPath(uri);
    return fs.readFileSync(filePath, "utf-8");
  } catch {
    return null;
  }
}

// deno-lint-ignore no-explicit-any
connection.onInitialize((params: any) => {
  const rootUri: string | undefined = params.rootUri ?? params.rootPath;
  if (rootUri) {
    try {
      workspaceRoot = rootUri.startsWith("file://")
        ? fileURLToPath(rootUri)
        : rootUri;
      scanCaffeineFiles(workspaceRoot);
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

// --- Workspace Blueprint Index ---

/** Maps file URIs to the set of blueprint item names they define. */
const blueprintIndex = new Map<string, Set<string>>();

/** Extract blueprint item names from a file's text. Returns empty array for non-blueprint files. */
function extractBlueprintNames(text: string): string[] {
  const trimmed = text.trimStart();
  if (!trimmed.startsWith("Blueprints")) return [];
  // Match all blueprint item names: * "name"
  const names: string[] = [];
  const pattern = /\*\s+"([^"]+)"/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    names.push(match[1]);
  }
  return names;
}

/** Collect all known blueprint names across the workspace. */
function allKnownBlueprints(): string[] {
  const names: string[] = [];
  for (const set of blueprintIndex.values()) {
    for (const name of set) {
      names.push(name);
    }
  }
  return names;
}

/** Check whether file content is an expects file. */
function isExpectsFile(text: string): boolean {
  return text.trimStart().startsWith("Expectations");
}

/** Convert a Gleam diagnostic to an LSP diagnostic. */
// deno-lint-ignore no-explicit-any
function gleamDiagToLsp(d: any) {
  const codeStr = diagnostic_code_to_string(d.code);
  const base = {
    range: range(d.line, d.column, d.line, d.end_column),
    severity: d.severity as DiagnosticSeverity,
    source: "caffeine",
    message: d.message,
  };
  return codeStr instanceof Some
    ? { ...base, code: codeStr[0] }
    : base;
}

/** Run cross-file diagnostics for all open expects files. */
function revalidateExpectsFiles() {
  const knownList = toList(allKnownBlueprints());
  for (const doc of documents.all()) {
    const text = doc.getText();
    if (!isExpectsFile(text)) continue;
    try {
      const singleDiags = gleamArray(get_diagnostics(text) as GleamList);
      const crossDiags = gleamArray(get_cross_file_diagnostics(text, knownList) as GleamList);
      const allDiags = [...singleDiags, ...crossDiags];
      connection.sendDiagnostics({
        uri: doc.uri,
        diagnostics: allDiags.map(gleamDiagToLsp),
      });
    } catch {
      /* ignore */
    }
  }
}

// --- Diagnostics ---

const diagnosticTimers = new Map<string, ReturnType<typeof setTimeout>>();

documents.onDidChangeContent((change) => {
  const uri = change.document.uri;

  // Debounce diagnostics to avoid running the full pipeline on every keystroke
  const existing = diagnosticTimers.get(uri);
  if (existing) clearTimeout(existing);

  diagnosticTimers.set(
    uri,
    setTimeout(() => {
      diagnosticTimers.delete(uri);
      const doc = documents.get(uri);
      if (!doc) return;
      const text = doc.getText();

      // Update blueprint index for this file
      const newNames = extractBlueprintNames(text);
      const oldNames = blueprintIndex.get(uri);
      if (newNames.length > 0) {
        blueprintIndex.set(uri, new Set(newNames));
      } else {
        blueprintIndex.delete(uri);
      }

      try {
        const singleDiags = gleamArray(get_diagnostics(text) as GleamList);

        // Add cross-file diagnostics for expects files
        let crossDiags: ReturnType<typeof gleamArray> = [];
        if (isExpectsFile(text)) {
          crossDiags = gleamArray(
            get_cross_file_diagnostics(text, toList(allKnownBlueprints())) as GleamList,
          );
        }

        const allDiags = [...singleDiags, ...crossDiags];
        connection.sendDiagnostics({
          uri,
          diagnostics: allDiags.map(gleamDiagToLsp),
        });
      } catch {
        connection.sendDiagnostics({ uri, diagnostics: [] });
      }

      // If blueprint index changed, re-validate all open expects files
      const namesChanged = !oldNames
        || oldNames.size !== newNames.length
        || newNames.some((n) => !oldNames.has(n));
      if (namesChanged && newNames.length > 0 || oldNames && newNames.length === 0) {
        revalidateExpectsFiles();
      }
    }, 300),
  );
});

// --- Hover ---

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

// --- Completion ---

connection.onCompletion((params) => {
  const doc = documents.get(params.textDocument.uri);
  const text = doc ? doc.getText() : "";

  try {
    const blueprintNames = toList(allKnownBlueprints());
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

// --- Formatting ---

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

// --- Document Symbols ---

// deno-lint-ignore no-explicit-any
function gleamSymbolToLsp(sym: any): any {
  const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
  return {
    name: sym.name,
    detail: sym.detail,
    kind: sym.kind,
    range: r,
    selectionRange: r,
    children: gleamArray(sym.children as GleamList).map(gleamSymbolToLsp),
  };
}

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

// --- Go to Definition ---

/** Find the location of a blueprint artifact header (Blueprints for "name") in a file. */
function findBlueprintArtifactLocation(
  text: string,
  artifactName: string,
): { line: number; col: number; nameLen: number } | null {
  const pattern = `Blueprints for "${artifactName}"`;
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const idx = lines[i].indexOf(pattern);
    if (idx < 0) continue;
    // Column of the artifact name (inside the quotes)
    const nameCol = idx + `Blueprints for "`.length;
    return { line: i, col: nameCol, nameLen: artifactName.length };
  }
  return null;
}

/** Look up a cross-file blueprint definition by artifact name. */
function findCrossFileBlueprintDef(
  artifactName: string,
): { uri: string; line: number; col: number; nameLen: number } | null {
  for (const uri of workspaceFiles) {
    const text = getFileContent(uri);
    if (!text) continue;
    // Quick check: skip files that don't contain the artifact name
    if (!text.includes(`Blueprints for "${artifactName}"`)) continue;
    const loc = findBlueprintArtifactLocation(text, artifactName);
    if (loc) return { uri, ...loc };
  }
  return null;
}

connection.onDefinition((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const text = doc.getText();

  try {
    // First: try in-file definition (existing behavior)
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

    // Second: try cross-file blueprint reference
    const bpRef = get_blueprint_ref_at_position(
      text,
      params.position.line,
      params.position.character,
    );
    if (bpRef instanceof Some) {
      const target = findCrossFileBlueprintDef(bpRef[0] as string);
      if (target) {
        return {
          uri: target.uri,
          range: range(target.line, target.col, target.line, target.col + target.nameLen),
        };
      }
    }
  } catch { /* ignore */ }
  return null;
});

// --- Declaration (delegates to definition) ---

connection.onDeclaration((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  const text = doc.getText();

  try {
    // First: try in-file definition
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

    // Second: try cross-file blueprint reference
    const bpRef = get_blueprint_ref_at_position(
      text,
      params.position.line,
      params.position.character,
    );
    if (bpRef instanceof Some) {
      const target = findCrossFileBlueprintDef(bpRef[0] as string);
      if (target) {
        return {
          uri: target.uri,
          range: range(target.line, target.col, target.line, target.col + target.nameLen),
        };
      }
    }
  } catch { /* ignore */ }
  return null;
});

// --- Document Highlight ---

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

// --- Find All References ---

connection.onReferences((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    const text = doc.getText();
    const line = params.position.line;
    const char = params.position.character;

    // Same-file references (extendables, type aliases, and blueprint names)
    const sameFileRefs = gleamArray(
      get_references(text, line, char) as GleamList,
    ).map((r) => ({
      uri: params.textDocument.uri,
      range: range(r[0], r[1], r[0], r[1] + r[2]),
    }));

    // Check if cursor is on a blueprint name for cross-file search
    const blueprintName = get_blueprint_name_at(text, line, char) as string;
    if (!blueprintName) return sameFileRefs;

    // Search all other open .caffeine documents for the same name
    const crossFileRefs: typeof sameFileRefs = [];
    for (const otherDoc of documents.all()) {
      if (otherDoc.uri === params.textDocument.uri) continue;
      if (!otherDoc.uri.endsWith(".caffeine")) continue;
      try {
        const otherRefs = gleamArray(
          find_references_to_name(otherDoc.getText(), blueprintName) as GleamList,
        );
        for (const r of otherRefs) {
          crossFileRefs.push({
            uri: otherDoc.uri,
            range: range(r[0], r[1], r[0], r[1] + r[2]),
          });
        }
      } catch { /* skip documents that fail */ }
    }

    return [...sameFileRefs, ...crossFileRefs];
  } catch {
    return [];
  }
});

// --- Rename ---

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

// --- Folding Ranges ---

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

// --- Selection Ranges ---

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

// deno-lint-ignore no-explicit-any
function gleamSelectionRangeToLsp(sr: any): any {
  const r = range(sr.start_line, sr.start_col, sr.end_line, sr.end_col);
  // HasParent wraps a SelectionRange at index [0]; NoParent has no such field
  const hasParent = sr.parent && sr.parent[0] !== undefined;
  return {
    range: r,
    parent: hasParent ? gleamSelectionRangeToLsp(sr.parent[0]) : undefined,
  };
}

// --- Linked Editing Ranges ---

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

// --- Semantic Tokens ---

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

// --- Code Actions ---

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

// --- Workspace Symbols ---

// deno-lint-ignore no-explicit-any
connection.onWorkspaceSymbol((params: any) => {
  const query = (params.query ?? "").toLowerCase();
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of workspaceFiles) {
    const text = getFileContent(uri);
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

// --- Type Hierarchy ---

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
connection.languages.typeHierarchy.onSupertypes((params: any) => {
  const data = params.item?.data;
  if (!data || data.kind !== "expectation" || !data.blueprint) return [];

  // Search workspace blueprint files for a blueprint item matching the referenced name
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];
  for (const uri of workspaceFiles) {
    const text = getFileContent(uri);
    if (!text || !text.trimStart().startsWith("Blueprints")) continue;
    // Quick check: does file contain the blueprint name?
    if (!text.includes(`"${data.blueprint}"`)) continue;

    try {
      // SymbolKind.Class (5) items from workspace symbols are blueprint/expect items
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
connection.languages.typeHierarchy.onSubtypes((params: any) => {
  const data = params.item?.data;
  if (!data || data.kind !== "blueprint") return [];

  const blueprintName = params.item.name;
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of workspaceFiles) {
    const text = getFileContent(uri);
    if (!text || !text.trimStart().startsWith("Expectations")) continue;
    // Quick check: does file reference this blueprint?
    if (!text.includes(`"${blueprintName}"`)) continue;

    try {
      // Use prepare_type_hierarchy on each expect item to get blueprint association.
      // Walk lines to find expect item names (lines matching * "name":).
      const lines = text.split("\n");
      for (let i = 0; i < lines.length; i++) {
        const match = lines[i].match(/^\s*\*\s+"([^"]+)"/);
        if (!match) continue;
        const itemName = match[1];
        // Use prepare_type_hierarchy to get the item with its blueprint reference
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

// --- Watched Files ---

connection.onDidChangeWatchedFiles((params) => {
  for (const change of params.changes) {
    const uri = change.uri;
    if (!uri.endsWith(".caffeine")) continue;
    if (change.type === FileChangeType.Deleted) {
      workspaceFiles.delete(uri);
    } else {
      workspaceFiles.add(uri);
    }
  }
});

// --- Document Close ---

documents.onDidClose((event) => {
  const uri = event.document.uri;
  const had = blueprintIndex.has(uri);
  blueprintIndex.delete(uri);
  // If a blueprints file was closed, re-validate expects files
  if (had) {
    revalidateExpectsFiles();
  }
});

documents.listen(connection);
connection.listen();
