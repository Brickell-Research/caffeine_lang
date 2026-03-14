// Type hierarchy LSP handlers — prepare, supertypes, subtypes.

import { SymbolKind } from "vscode-languageserver/node.js";
import {
  prepare_type_hierarchy,
  MeasurementKind,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  range,
} from "./helpers.ts";

import type { HandlerContext } from "./handlers.ts";
import { debug } from "./debug.ts";

// --- Type hierarchy: prepare ---

// deno-lint-ignore no-explicit-any
export function handleTypeHierarchyPrepare(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  try {
    const items = gleamArray(
      prepare_type_hierarchy(doc.getText(), params.position.line, params.position.character) as GleamList,
    );
    if (items.length === 0) return null;
    return items.map((item) => {
      const r = range(item.line, item.col, item.line, item.col + item.name_len);
      return {
        name: item.name,
        kind: SymbolKind.Class,
        uri: params.textDocument.uri,
        range: r,
        selectionRange: r,
        data: {
          kind: item.kind instanceof MeasurementKind ? "measurement" : "expectation",
          measurement: item.measurement,
        },
      };
    });
  } catch (e) {
    debug(`typeHierarchyPrepare: ${e}`);
    return null;
  }
}

// --- Type hierarchy: supertypes ---

// deno-lint-ignore no-explicit-any
export async function handleTypeHierarchySupertypes(ctx: HandlerContext, params: any) {
  const data = params.item?.data;
  if (!data || data.kind !== "expectation" || !data.measurement) return [];

  // deno-lint-ignore no-explicit-any
  const results: any[] = [];
  for (const uri of ctx.workspace.files) {
    const text = await ctx.workspace.getFileContentAsync(uri);
    if (!text || !text.trimStart().startsWith("Measurements")) continue;
    if (!text.includes(`"${data.measurement}"`)) continue;

    for (const sym of ctx.workspace.getCachedWorkspaceSymbols(uri, text)) {
      if (sym.name === data.measurement && sym.kind === SymbolKind.Class) {
        const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
        results.push({
          name: sym.name, kind: SymbolKind.Class, uri, range: r, selectionRange: r,
          data: { kind: "measurement", measurement: "" },
        });
      }
    }
  }

  return results;
}

// --- Type hierarchy: subtypes ---

// deno-lint-ignore no-explicit-any
export async function handleTypeHierarchySubtypes(ctx: HandlerContext, params: any) {
  const data = params.item?.data;
  if (!data || data.kind !== "measurement") return [];

  const measurementName = params.item.name;
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of ctx.workspace.files) {
    const text = await ctx.workspace.getFileContentAsync(uri);
    if (!text || !text.trimStart().startsWith("Expectations")) continue;
    if (!text.includes(`"${measurementName}"`)) continue;

    try {
      collectSubtypesFromFile(text, measurementName, uri, results);
    } catch (e) { debug(`typeHierarchySubtypes: ${e}`); }
  }

  return results;
}

// deno-lint-ignore no-explicit-any
function collectSubtypesFromFile(text: string, measurementName: string, uri: string, results: any[]): void {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*\*\s+"([^"]+)"/);
    if (!match) continue;
    const itemName = match[1];
    for (const item of gleamArray(
      prepare_type_hierarchy(text, i, lines[i].indexOf(itemName)) as GleamList,
    )) {
      if (item.measurement === measurementName) {
        const r = range(item.line, item.col, item.line, item.col + item.name_len);
        results.push({
          name: item.name, kind: SymbolKind.Class, uri, range: r, selectionRange: r,
          data: { kind: "expectation", measurement: measurementName },
        });
      }
    }
  }
}
