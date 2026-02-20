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
import { get_all_diagnostics, diagnostic_code_to_string, QuotedFieldName, BlueprintNotFound, DependencyNotFound, NoDiagnosticCode } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/diagnostics.mjs";
import { get_hover } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/hover.mjs";
import { get_completions } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/completion.mjs";
import {
  get_semantic_tokens,
  token_types,
} from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/semantic_tokens.mjs";
import { get_symbols } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/document_symbols.mjs";
import { get_definition, get_blueprint_ref_at_position, get_relation_ref_with_range_at_position } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/definition.mjs";
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
async function scanCaffeineFiles(dir: string): Promise<void> {
  let entries: fs.Dirent[];
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await scanCaffeineFiles(full);
    } else if (entry.isFile() && entry.name.endsWith(".caffeine")) {
      workspaceFiles.add(pathToFileURL(full).toString());
    }
  }
}

/** Read file content: prefer open document, fall back to async disk read. */
async function getFileContentAsync(uri: string): Promise<string | null> {
  const doc = documents.get(uri);
  if (doc) return doc.getText();
  try {
    const filePath = fileURLToPath(uri);
    return await fs.promises.readFile(filePath, "utf-8");
  } catch {
    return null;
  }
}

// deno-lint-ignore no-explicit-any
connection.onInitialize(async (params: any) => {
  const rootUri: string | undefined = params.rootUri ?? params.rootPath;
  if (rootUri) {
    try {
      workspaceRoot = rootUri.startsWith("file://")
        ? fileURLToPath(rootUri)
        : rootUri;
      await scanCaffeineFiles(workspaceRoot);
      // Build initial blueprint and expectation indices from all discovered files
      for (const uri of workspaceFiles) {
        const text = await getFileContentAsync(uri);
        if (text) {
          const names = extractBlueprintNames(text);
          if (names.length > 0) {
            blueprintIndex.set(uri, new Set(names));
          }
          const ids = extractExpectationIdentifiers(text, uri);
          if (ids.size > 0) {
            expectationIndex.set(uri, ids);
          }
        }
      }
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
  if (!text.includes("Blueprints for")) return [];
  // Match blueprint item names: * "name" — only on non-comment lines
  const names: string[] = [];
  const pattern = /\*\s+"([^"]+)"/;
  for (const line of text.split("\n")) {
    if (line.trimStart().startsWith("#")) continue;
    const match = pattern.exec(line);
    if (match) names.push(match[1]);
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

// --- Workspace Expectation Index ---

/** Maps file URIs to expectation item names and their dotted identifiers. */
const expectationIndex = new Map<string, Map<string, string>>();

/** Extract org/team/service from a file path (last 3 path segments). */
function extractPathPrefix(filePath: string): [string, string, string] {
  const segments = filePath.split(path.sep);
  const last3 = segments.slice(-3);
  if (last3.length < 3) return ["unknown", "unknown", "unknown"];
  const [org, team, serviceFile] = last3;
  const service = serviceFile.replace(/\.caffeine$/, "").replace(/\.json$/, "");
  return [org, team, service];
}

/** Extract expectation identifiers (org.team.service.name) from an expects file. */
function extractExpectationIdentifiers(
  text: string,
  uri: string,
): Map<string, string> {
  const result = new Map<string, string>();
  if (!text.includes("Expectations for")) return result;

  let filePath: string;
  try {
    filePath = fileURLToPath(uri);
  } catch {
    return result;
  }
  const [org, team, service] = extractPathPrefix(filePath);

  const pattern = /\*\s+"([^"]+)"/;
  for (const line of text.split("\n")) {
    if (line.trimStart().startsWith("#")) continue;
    const match = pattern.exec(line);
    if (match) {
      const name = match[1];
      result.set(name, `${org}.${team}.${service}.${name}`);
    }
  }
  return result;
}

/** Collect all known expectation dotted identifiers across the workspace. */
function allKnownExpectationIdentifiers(): string[] {
  const ids: string[] = [];
  for (const idMap of expectationIndex.values()) {
    for (const dottedId of idMap.values()) {
      ids.push(dottedId);
    }
  }
  return ids;
}

/** Look up an expectation definition by dotted identifier. */
async function findExpectationByIdentifier(
  dottedId: string,
): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
  const parts = dottedId.split(".");
  if (parts.length !== 4) return null;
  const itemName = parts[3];

  for (const [uri, idMap] of expectationIndex) {
    if (idMap.get(itemName) !== dottedId) continue;
    const text = await getFileContentAsync(uri);
    if (!text) continue;
    // Reuse blueprint item location finder — same * "name" pattern
    const loc = findBlueprintItemLocation(text, itemName);
    if (loc) return { uri, ...loc };
  }
  return null;
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

/** Run all diagnostics for all open documents using single-parse path. */
function revalidateCrossFileDiagnostics() {
  const knownBlueprints = toList(allKnownBlueprints());
  const knownExpectations = toList(allKnownExpectationIdentifiers());
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

// --- Index Update Helper ---

/** Updates both blueprint and expectation indices for a file. Returns true if either changed. */
function updateIndicesForFile(uri: string, text: string): boolean {
  let changed = false;

  const newNames = extractBlueprintNames(text);
  const oldNames = blueprintIndex.get(uri);
  if (newNames.length > 0) {
    blueprintIndex.set(uri, new Set(newNames));
  } else {
    blueprintIndex.delete(uri);
  }
  const namesChanged = !oldNames
    || oldNames.size !== newNames.length
    || newNames.some((n) => !oldNames.has(n));
  if ((namesChanged && newNames.length > 0) || (oldNames && newNames.length === 0)) {
    changed = true;
  }

  const newIds = extractExpectationIdentifiers(text, uri);
  const oldIds = expectationIndex.get(uri);
  if (newIds.size > 0) {
    expectationIndex.set(uri, newIds);
  } else {
    expectationIndex.delete(uri);
  }
  const idsChanged = !oldIds
    || oldIds.size !== newIds.size
    || [...newIds.entries()].some(([k, v]) => oldIds.get(k) !== v);
  if ((idsChanged && newIds.size > 0) || (oldIds && newIds.size === 0)) {
    changed = true;
  }

  return changed;
}

/** Coalesce rapid revalidation triggers into a single trailing-edge run. */
let revalidateTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleRevalidation() {
  if (revalidateTimer) clearTimeout(revalidateTimer);
  revalidateTimer = setTimeout(() => {
    revalidateTimer = null;
    revalidateCrossFileDiagnostics();
  }, 50);
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

      if (updateIndicesForFile(uri, text)) {
        // Indices changed — revalidate all open documents (includes current file)
        scheduleRevalidation();
      } else {
        // No index changes — only send diagnostics for the current file
        try {
          const allDiags = gleamArray(
            get_all_diagnostics(
              text,
              toList(allKnownBlueprints()),
              toList(allKnownExpectationIdentifiers()),
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

/** Find the location of a blueprint item (e.g. * "name") within a blueprint file. */
function findBlueprintItemLocation(
  text: string,
  itemName: string,
): { line: number; col: number; nameLen: number } | null {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    // Match blueprint item pattern: * "itemName"
    if (!/^\s*\*\s+"/.test(lines[i])) continue;
    const nameIdx = lines[i].indexOf(`"${itemName}"`);
    if (nameIdx < 0) continue;
    // Column is inside the quotes (skip the opening quote)
    return { line: i, col: nameIdx + 1, nameLen: itemName.length };
  }
  return null;
}

/** Look up a cross-file blueprint definition by blueprint item name. */
async function findCrossFileBlueprintDef(
  blueprintItemName: string,
): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
  // Use the blueprint index for a fast lookup by item name
  for (const [uri, names] of blueprintIndex) {
    if (!names.has(blueprintItemName)) continue;
    const text = await getFileContentAsync(uri);
    if (!text) continue;
    const loc = findBlueprintItemLocation(text, blueprintItemName);
    if (loc) return { uri, ...loc };
  }
  return null;
}

/** Shared async handler for definition and declaration requests. */
// deno-lint-ignore no-explicit-any
async function resolveDefinitionOrDeclaration(params: any) {
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
      const target = await findCrossFileBlueprintDef(bpRef[0] as string);
      if (target) {
        return {
          uri: target.uri,
          range: range(target.line, target.col, target.line, target.col + target.nameLen),
        };
      }
    }

    // Third: try dependency relation reference
    const relRefWithRange = get_relation_ref_with_range_at_position(
      text,
      params.position.line,
      params.position.character,
    );
    if (relRefWithRange instanceof Some) {
      const refStr = relRefWithRange[0][0] as string;
      const refStartCol = relRefWithRange[0][1] as number;
      const refLen = refStr.length;
      const target = await findExpectationByIdentifier(refStr);
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

connection.onReferences(async (params) => {
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

    // Search all workspace .caffeine files (not just open ones) for references
    const crossFileRefs: typeof sameFileRefs = [];
    const searched = new Set<string>([params.textDocument.uri]);
    for (const uri of workspaceFiles) {
      if (searched.has(uri)) continue;
      searched.add(uri);
      const otherText = await getFileContentAsync(uri);
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

// --- Workspace Symbols ---

// deno-lint-ignore no-explicit-any
connection.onWorkspaceSymbol(async (params: any) => {
  const query = (params.query ?? "").toLowerCase();
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of workspaceFiles) {
    const text = await getFileContentAsync(uri);
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
connection.languages.typeHierarchy.onSupertypes(async (params: any) => {
  const data = params.item?.data;
  if (!data || data.kind !== "expectation" || !data.blueprint) return [];

  // Search workspace blueprint files for a blueprint item matching the referenced name
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];
  for (const uri of workspaceFiles) {
    const text = await getFileContentAsync(uri);
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
connection.languages.typeHierarchy.onSubtypes(async (params: any) => {
  const data = params.item?.data;
  if (!data || data.kind !== "blueprint") return [];

  const blueprintName = params.item.name;
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of workspaceFiles) {
    const text = await getFileContentAsync(uri);
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

connection.onDidChangeWatchedFiles(async (params) => {
  let indicesChanged = false;
  for (const change of params.changes) {
    const uri = change.uri;
    if (!uri.endsWith(".caffeine")) continue;

    if (change.type === FileChangeType.Deleted) {
      workspaceFiles.delete(uri);
      if (blueprintIndex.has(uri)) {
        blueprintIndex.delete(uri);
        indicesChanged = true;
      }
      if (expectationIndex.has(uri)) {
        expectationIndex.delete(uri);
        indicesChanged = true;
      }
    } else {
      // Created or Changed — update workspace tracking and indices
      workspaceFiles.add(uri);
      const text = await getFileContentAsync(uri);
      if (text && updateIndicesForFile(uri, text)) {
        indicesChanged = true;
      }
    }
  }

  if (indicesChanged) {
    scheduleRevalidation();
  }
});

// --- Document Close ---

documents.onDidClose((event) => {
  const uri = event.document.uri;
  // Clear diagnostics for the closed document so stale markers don't linger
  connection.sendDiagnostics({ uri, diagnostics: [] });

  // Capture index state before the async read so we detect changes correctly.
  const hadBlueprintsBefore = blueprintIndex.has(uri);
  const hadExpectationsBefore = expectationIndex.has(uri);

  // Re-read from disk to keep the blueprint index accurate (the file still exists,
  // we just closed the editor tab). Use async read to avoid blocking.
  (async () => {
    let diskText: string | null = null;
    try {
      diskText = await fs.promises.readFile(fileURLToPath(uri), "utf-8");
    } catch {
      // File may have been deleted
    }

    if (diskText) {
      updateIndicesForFile(uri, diskText);
    } else {
      // File was deleted from disk while open — clean up
      blueprintIndex.delete(uri);
      expectationIndex.delete(uri);
    }

    const hasBlueprintsAfter = blueprintIndex.has(uri);
    const hasExpectationsAfter = expectationIndex.has(uri);
    // If any index availability changed, re-validate open documents
    if (hadBlueprintsBefore || hasBlueprintsAfter || hadExpectationsBefore || hasExpectationsAfter) {
      scheduleRevalidation();
    }
  })().catch(() => { /* async close handler — errors are non-fatal */ });
});

documents.listen(connection);
connection.listen();
