// Single-document LSP feature handlers — hover, completion, formatting,
// code actions, rename, symbols, tokens, folding, selection, linked editing.

import {
  get_hover,
  get_completions,
  get_signature_help,
  get_inlay_hints,
  get_semantic_tokens,
  get_symbols,
  get_code_actions,
  ActionDiagnostic,
  QuotedFieldName,
  MeasurementNotFound,
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
import type { SloStatusCache } from "./vendors/slo_cache.ts";
import { debug } from "./debug.ts";

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
      ctx.workspace.allValidatedMeasurements(),
    );
    if (result instanceof Some) {
      return { contents: { kind: "markdown" as const, value: result[0] } };
    }
  } catch (e) { debug(`hover: ${e}`); }
  return null;
}

// --- Completion ---

// deno-lint-ignore no-explicit-any
export function handleCompletion(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];
  const text = doc.getText();

  try {
    const measurementNames = toList(ctx.workspace.allKnownMeasurements());
    const validatedMeasurements = ctx.workspace.allValidatedMeasurements();
    const items = gleamArray(
      get_completions(text, params.position.line, params.position.character, measurementNames, validatedMeasurements) as GleamList,
    );
    return items.map((item) => ({
      label: item.label,
      kind: item.kind,
      detail: item.detail,
      ...(item.insert_text instanceof Some ? { insertText: item.insert_text[0] } : {}),
      ...(item.insert_text_format instanceof Some ? { insertTextFormat: item.insert_text_format[0] } : {}),
    }));
  } catch (e) {
    debug(`completion: ${e}`);
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
  } catch (e) {
    debug(`highlight: ${e}`);
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
  } catch (e) { debug(`formatting: ${e}`); }
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
              : d.code === "measurement-not-found" ? new MeasurementNotFound()
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
  } catch (e) {
    debug(`codeAction: ${e}`);
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
  } catch (e) { debug(`prepareRename: ${e}`); }
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
  } catch (e) {
    debug(`rename: ${e}`);
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
  } catch (e) {
    debug(`documentSymbol: ${e}`);
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
  } catch (e) {
    debug(`semanticTokens: ${e}`);
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
  } catch (e) {
    debug(`foldingRanges: ${e}`);
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
  } catch (e) {
    debug(`selectionRanges: ${e}`);
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
  } catch (e) {
    debug(`linkedEditing: ${e}`);
    return null;
  }
}

// --- Signature help ---

// deno-lint-ignore no-explicit-any
export function handleSignatureHelp(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const result = get_signature_help(
      doc.getText(),
      params.position.line,
      params.position.character,
      ctx.workspace.allValidatedMeasurements(),
    );
    if (result instanceof Some) {
      const sig = result[0];
      const sigParams = gleamArray(sig.parameters as GleamList);
      return {
        signatures: [{
          label: sig.label,
          parameters: sigParams.map((p: { label: string; documentation: string }) => ({
            label: p.label,
            documentation: p.documentation,
          })),
          activeParameter: sig.active_parameter,
        }],
        activeSignature: 0,
        activeParameter: sig.active_parameter,
      };
    }
  } catch (e) { debug(`signatureHelp: ${e}`); }
  return null;
}

// --- Inlay hints ---

// deno-lint-ignore no-explicit-any
export function handleInlayHints(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    const hints = gleamArray(
      get_inlay_hints(
        doc.getText(),
        params.range.start.line,
        params.range.end.line,
        ctx.workspace.allValidatedMeasurements(),
      ) as GleamList,
    );
    return hints.map((h: { line: number; column: number; label: string; kind: number; padding_left: boolean }) => ({
      position: { line: h.line, character: h.column },
      label: h.label,
      kind: h.kind,
      paddingLeft: h.padding_left,
    }));
  } catch (e) {
    debug(`inlayHints: ${e}`);
    return [];
  }
}

// --- Code lenses (SLO overlay) ---

/** Extract expectation item names and their line positions from an expects file. */
export function extractExpectationPositions(text: string): Array<{ name: string; line: number }> {
  const results: Array<{ name: string; line: number }> = [];
  if (!text.includes("Expectations measured by")) return results;

  const lines = text.split("\n");
  const pattern = /\*\s+"([^"]+)"/;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trimStart().startsWith("#")) continue;
    const match = pattern.exec(lines[i]);
    if (match) results.push({ name: match[1], line: i });
  }
  return results;
}

/** Format an SLO status into a human-readable code lens title. */
export function formatSloLensTitle(slo: { sli_value: number; target: number; error_budget_remaining: number; window: string; status: string }): string {
  const sli = slo.sli_value.toFixed(2);
  const target = slo.target.toFixed(1);
  const budget = slo.error_budget_remaining.toFixed(1);
  const icon = slo.status === "breaching" ? " 🔴" : slo.status === "warning" ? " ⚠️" : " 🟢";
  return `SLI: ${sli}% | Target: ${target}% | Budget: ${budget}% remaining | ${slo.window}${icon}`;
}

// deno-lint-ignore no-explicit-any
export function handleCodeLens(ctx: HandlerContext, params: any, sloCache: SloStatusCache | null) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  const uri = params.textDocument.uri;
  const text = doc.getText();
  const items = extractExpectationPositions(text);
  if (items.length === 0) return [];

  // deno-lint-ignore no-explicit-any
  const lenses: any[] = [];

  for (const item of items) {
    const vendor = ctx.workspace.getVendorForItem(uri, item.name);
    if (vendor !== "datadog") continue;

    if (!sloCache) {
      lenses.push({
        range: range(item.line, 0, item.line, 0),
        command: { title: "Add DD_API_KEY + DD_APP_KEY to .env to see SLO status", command: "" },
      });
      continue;
    }

    const dottedId = ctx.workspace.getDottedIdForItem(uri, item.name);
    if (!dottedId) continue;

    const sloStatuses = sloCache.get(dottedId);

    if (sloStatuses) {
      for (const slo of sloStatuses) {
        const title = formatSloLensTitle(slo);
        const command = slo.dashboard_url
          ? { title, command: "vscode.open", arguments: [slo.dashboard_url] }
          : { title, command: "" };
        lenses.push({ range: range(item.line, 0, item.line, 0), command });
      }
    } else {
      const title = sloCache.hasFetched ? "SLO not found in Datadog" : "SLO data loading...";
      lenses.push({
        range: range(item.line, 0, item.line, 0),
        command: { title, command: "" },
      });
    }
  }

  return lenses;
}
