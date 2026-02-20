// Single-document LSP feature handlers — hover, completion, formatting,
// code actions, rename, symbols, tokens, folding, selection, linked editing.

import {
  get_hover,
  get_completions,
  get_semantic_tokens,
  get_symbols,
  get_code_actions,
  ActionDiagnostic,
  QuotedFieldName,
  BlueprintNotFound,
  DependencyNotFound,
  NoDiagnosticCode,
  format,
  get_highlights,
  prepare_rename,
  get_rename_edits,
  get_folding_ranges,
  get_selection_range,
  get_linked_editing_ranges,
  Ok,
  toList,
  Some,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  range,
  gleamSymbolToLsp,
  gleamSelectionRangeToLsp,
} from "./helpers.ts";

import type { HandlerContext } from "./handlers.ts";

// --- Hover ---

// deno-lint-ignore no-explicit-any
export function handleHover(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const result = get_hover(
      doc.getText(),
      params.position.line,
      params.position.character,
    );
    if (result instanceof Some) {
      return { contents: { kind: "markdown" as const, value: result[0] } };
    }
  } catch { /* ignore */ }
  return null;
}

// --- Completion ---

// deno-lint-ignore no-explicit-any
export function handleCompletion(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  const text = doc ? doc.getText() : "";

  try {
    const blueprintNames = toList(ctx.workspace.allKnownBlueprints());
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
}

// --- Document highlight ---

// deno-lint-ignore no-explicit-any
export function handleHighlight(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    const highlights = gleamArray(
      get_highlights(doc.getText(), params.position.line, params.position.character) as GleamList,
    );
    return highlights.map((h) => ({
      range: range(h[0], h[1], h[0], h[1] + h[2]),
      kind: 1,
    }));
  } catch {
    return [];
  }
}

// --- Formatting ---

// deno-lint-ignore no-explicit-any
export function handleFormatting(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  const text = doc.getText();
  try {
    const result = format(text);
    if (result instanceof Ok) {
      return [{ range: range(0, 0, text.split("\n").length, 0), newText: result[0] }];
    }
  } catch { /* ignore */ }
  return [];
}

// --- Code actions ---

// deno-lint-ignore no-explicit-any
export function handleCodeAction(_ctx: HandlerContext, params: any) {
  const uri = params.textDocument.uri;

  try {
    const gleamDiags = toList(
      params.context.diagnostics.map(
        // deno-lint-ignore no-explicit-any
        (d: any) =>
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
        diagnostics: [{
          message: diag.message,
          source: "caffeine",
          range: range(diag.line, diag.character, diag.end_line, diag.end_character),
        }],
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
}

// --- Prepare rename ---

// deno-lint-ignore no-explicit-any
export function handlePrepareRename(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const result = prepare_rename(doc.getText(), params.position.line, params.position.character);
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
}

// --- Rename ---

// deno-lint-ignore no-explicit-any
export function handleRename(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
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
}

// --- Document symbols ---

// deno-lint-ignore no-explicit-any
export function handleDocumentSymbol(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    return gleamArray(get_symbols(doc.getText()) as GleamList).map(gleamSymbolToLsp);
  } catch {
    return [];
  }
}

// --- Semantic tokens ---

// deno-lint-ignore no-explicit-any
export function handleSemanticTokens(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return { data: [] };

  try {
    return { data: gleamArray(get_semantic_tokens(doc.getText()) as GleamList) };
  } catch {
    return { data: [] };
  }
}

// --- Folding ranges ---

// deno-lint-ignore no-explicit-any
export function handleFoldingRanges(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    return gleamArray(get_folding_ranges(doc.getText()) as GleamList).map((r) => ({
      startLine: r.start_line,
      endLine: r.end_line,
      kind: "region" as const,
    }));
  } catch {
    return [];
  }
}

// --- Selection ranges ---

// deno-lint-ignore no-explicit-any
export function handleSelectionRanges(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    return params.positions.map((pos: { line: number; character: number }) => {
      return gleamSelectionRangeToLsp(get_selection_range(doc.getText(), pos.line, pos.character));
    });
  } catch {
    return [];
  }
}

// --- Linked editing ranges ---

// deno-lint-ignore no-explicit-any
export function handleLinkedEditing(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const ranges = gleamArray(
      get_linked_editing_ranges(doc.getText(), params.position.line, params.position.character) as GleamList,
    );
    if (ranges.length === 0) return null;
    return { ranges: ranges.map((r) => range(r[0], r[1], r[0], r[1] + r[2])) };
  } catch {
    return null;
  }
}
