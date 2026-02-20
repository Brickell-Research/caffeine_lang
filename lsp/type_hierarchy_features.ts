// Type hierarchy LSP handlers — prepare, supertypes, subtypes.

import {
  get_workspace_symbols,
  prepare_type_hierarchy,
  BlueprintKind,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  range,
} from "./helpers.ts";

import type { HandlerContext } from "./handlers.ts";

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
        kind: 5,
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
}

// --- Type hierarchy: supertypes ---

// deno-lint-ignore no-explicit-any
export async function handleTypeHierarchySupertypes(ctx: HandlerContext, params: any) {
  const data = params.item?.data;
  if (!data || data.kind !== "expectation" || !data.blueprint) return [];

  // deno-lint-ignore no-explicit-any
  const results: any[] = [];
  for (const uri of ctx.workspace.files) {
    const text = await ctx.workspace.getFileContentAsync(uri);
    if (!text || !text.trimStart().startsWith("Blueprints")) continue;
    if (!text.includes(`"${data.blueprint}"`)) continue;

    try {
      for (const sym of gleamArray(get_workspace_symbols(text) as GleamList)) {
        if (sym.name === data.blueprint && sym.kind === 5) {
          const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
          results.push({
            name: sym.name, kind: 5, uri, range: r, selectionRange: r,
            data: { kind: "blueprint", blueprint: "" },
          });
        }
      }
    } catch { /* ignore */ }
  }

  return results;
}

// --- Type hierarchy: subtypes ---

// deno-lint-ignore no-explicit-any
export async function handleTypeHierarchySubtypes(ctx: HandlerContext, params: any) {
  const data = params.item?.data;
  if (!data || data.kind !== "blueprint") return [];

  const blueprintName = params.item.name;
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of ctx.workspace.files) {
    const text = await ctx.workspace.getFileContentAsync(uri);
    if (!text || !text.trimStart().startsWith("Expectations")) continue;
    if (!text.includes(`"${blueprintName}"`)) continue;

    try {
      collectSubtypesFromFile(text, blueprintName, uri, results);
    } catch { /* ignore */ }
  }

  return results;
}

// deno-lint-ignore no-explicit-any
function collectSubtypesFromFile(text: string, blueprintName: string, uri: string, results: any[]): void {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*\*\s+"([^"]+)"/);
    if (!match) continue;
    const itemName = match[1];
    for (const item of gleamArray(
      prepare_type_hierarchy(text, i, lines[i].indexOf(itemName)) as GleamList,
    )) {
      if (item.blueprint === blueprintName) {
        const r = range(item.line, item.col, item.line, item.col + item.name_len);
        results.push({
          name: item.name, kind: 5, uri, range: r, selectionRange: r,
          data: { kind: "expectation", blueprint: blueprintName },
        });
      }
    }
  }
}
