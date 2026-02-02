// TypeScript LSP server wrapping Gleam intelligence modules.
// Uses vscode-languageserver-node for protocol handling, delegates all
// language logic to the compiled Gleam modules.

import {
  createConnection,
  TextDocuments,
  ProposedFeatures,
  TextDocumentSyncKind,
  DiagnosticSeverity,
} from "npm:vscode-languageserver/node";
import { TextDocument } from "npm:vscode-languageserver-textdocument";

// Gleam-compiled intelligence modules
import { get_diagnostics } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/diagnostics.mjs";
import { get_hover } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/hover.mjs";
import { get_completions } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/completion.mjs";
import {
  get_semantic_tokens,
  token_types,
} from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/semantic_tokens.mjs";
import { get_symbols } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/document_symbols.mjs";
import { get_definition } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/definition.mjs";
import { get_code_actions, ActionDiagnostic } from "./caffeine_lsp/build/dev/javascript/caffeine_lsp/caffeine_lsp/code_actions.mjs";
import { format } from "./caffeine_lsp/build/dev/javascript/caffeine_lang/caffeine_lang/frontend/formatter.mjs";

// Gleam runtime types
import { Ok, toList } from "./caffeine_lsp/build/dev/javascript/prelude.mjs";
import { Some } from "./caffeine_lsp/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

// deno-lint-ignore no-explicit-any
type GleamList = { toArray(): any[] };

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

connection.onInitialize(() => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Full,
      hoverProvider: true,
      definitionProvider: true,
      documentFormattingProvider: true,
      documentSymbolProvider: true,
      completionProvider: {
        triggerCharacters: [":", "["],
      },
      codeActionProvider: {
        codeActionKinds: ["quickfix"],
      },
      semanticTokensProvider: {
        legend: {
          tokenTypes: (token_types as GleamList).toArray(),
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

// --- Diagnostics ---

documents.onDidChangeContent((change) => {
  const text = change.document.getText();
  const uri = change.document.uri;

  try {
    const diags = (get_diagnostics(text) as GleamList).toArray();
    connection.sendDiagnostics({
      uri,
      diagnostics: diags.map((d) => ({
        range: {
          start: { line: d.line, character: d.column },
          end: { line: d.line, character: d.end_column },
        },
        severity: d.severity as DiagnosticSeverity,
        source: "caffeine",
        message: d.message,
      })),
    });
  } catch {
    connection.sendDiagnostics({ uri, diagnostics: [] });
  }
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
    const items = (
      get_completions(text, params.position.line, params.position.character) as GleamList
    ).toArray();
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
          range: {
            start: { line: 0, character: 0 },
            end: { line: lineCount, character: 0 },
          },
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
  const range = {
    start: { line: sym.line, character: sym.col },
    end: { line: sym.line, character: sym.col + sym.name_len },
  };
  return {
    name: sym.name,
    detail: sym.detail,
    kind: sym.kind,
    range,
    selectionRange: range,
    children: (sym.children as GleamList).toArray().map(gleamSymbolToLsp),
  };
}

connection.onDocumentSymbol((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    const symbols = (get_symbols(doc.getText()) as GleamList).toArray();
    return symbols.map(gleamSymbolToLsp);
  } catch {
    return [];
  }
});

// --- Go to Definition ---

connection.onDefinition((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const result = get_definition(
      doc.getText(),
      params.position.line,
      params.position.character,
    );
    if (result instanceof Some) {
      const [defLine, defCol, nameLen] = [result[0][0], result[0][1], result[0][2]];
      return {
        uri: params.textDocument.uri,
        range: {
          start: { line: defLine, character: defCol },
          end: { line: defLine, character: defCol + nameLen },
        },
      };
    }
  } catch { /* ignore */ }
  return null;
});

// --- Semantic Tokens ---

connection.languages.semanticTokens.on((params) => {
  const doc = documents.get(params.textDocument.uri);
  if (!doc) return { data: [] };

  try {
    const data = (get_semantic_tokens(doc.getText()) as GleamList).toArray();
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
          ),
      ),
    );

    const actions = (get_code_actions(gleamDiags, uri) as GleamList).toArray();
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
            range: {
              start: { line: diag.line, character: diag.character },
              end: { line: diag.end_line, character: diag.end_character },
            },
          },
        ],
        edit: {
          changes: {
            [action.uri]: (action.edits as GleamList).toArray().map((e) => ({
              range: {
                start: { line: e.start_line, character: e.start_character },
                end: { line: e.end_line, character: e.end_character },
              },
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

documents.listen(connection);
connection.listen();
