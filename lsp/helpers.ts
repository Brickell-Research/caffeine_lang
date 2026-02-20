// Pure LSP conversion utilities — no side effects, no connection state.

import { DiagnosticSeverity } from "npm:vscode-languageserver/node.js";
import { diagnostic_code_to_string, Some } from "./gleam_imports.ts";

// deno-lint-ignore no-explicit-any
export type GleamList = { toArray(): any[] };

/** Convert a GleamList to a plain JS array. */
// deno-lint-ignore no-explicit-any
export function gleamArray(gl: GleamList): any[] {
  return gl.toArray();
}

/** Build an LSP Range from line/col positions. */
export function range(
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

/** Convert a Gleam diagnostic to an LSP diagnostic. */
// deno-lint-ignore no-explicit-any
export function gleamDiagToLsp(d: any) {
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

/** Convert a Gleam document symbol to an LSP DocumentSymbol (recursive). */
// deno-lint-ignore no-explicit-any
export function gleamSymbolToLsp(sym: any): any {
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

/** Convert a Gleam SelectionRange to an LSP SelectionRange (recursive). */
// deno-lint-ignore no-explicit-any
export function gleamSelectionRangeToLsp(sr: any): any {
  const r = range(sr.start_line, sr.start_col, sr.end_line, sr.end_col);
  // HasParent wraps a SelectionRange at index [0]; NoParent has no such field
  const hasParent = sr.parent && sr.parent[0] !== undefined;
  return {
    range: r,
    parent: hasParent ? gleamSelectionRangeToLsp(sr.parent[0]) : undefined,
  };
}
