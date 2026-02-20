// Cross-file navigation handlers — definition, references, workspace symbols.

import {
  get_definition,
  get_blueprint_ref_at_position,
  get_relation_ref_with_range_at_position,
  get_references,
  get_blueprint_name_at,
  find_references_to_name,
  get_workspace_symbols,
  Some,
} from "./gleam_imports.ts";

import {
  type GleamList,
  gleamArray,
  range,
} from "./helpers.ts";

import type { HandlerContext } from "./handlers.ts";

// --- Definition / Declaration ---

// deno-lint-ignore no-explicit-any
export async function handleDefinition(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return null;

  const text = doc.getText();

  try {
    // In-file definition (extendables, type aliases)
    const result = get_definition(text, params.position.line, params.position.character);
    if (result instanceof Some) {
      const [defLine, defCol, nameLen] = [result[0][0], result[0][1], result[0][2]];
      return {
        uri: params.textDocument.uri,
        range: range(defLine, defCol, defLine, defCol + nameLen),
      };
    }

    // Cross-file blueprint reference
    const bpRef = get_blueprint_ref_at_position(text, params.position.line, params.position.character);
    if (bpRef instanceof Some) {
      const target = await ctx.workspace.findCrossFileBlueprintDef(bpRef[0] as string);
      if (target) {
        return {
          uri: target.uri,
          range: range(target.line, target.col, target.line, target.col + target.nameLen),
        };
      }
    }

    // Dependency relation reference
    const relRef = get_relation_ref_with_range_at_position(text, params.position.line, params.position.character);
    if (relRef instanceof Some) {
      const refStr = relRef[0][0] as string;
      const refStartCol = relRef[0][1] as number;
      const target = await ctx.workspace.findExpectationByIdentifier(refStr);
      if (target) {
        const srcLine = params.position.line;
        return [{
          originSelectionRange: range(srcLine, refStartCol, srcLine, refStartCol + refStr.length),
          targetUri: target.uri,
          targetRange: range(target.line, target.col, target.line, target.col + target.nameLen),
          targetSelectionRange: range(target.line, target.col, target.line, target.col + target.nameLen),
        }];
      }
    }
  } catch { /* ignore */ }
  return null;
}

// --- References ---

// deno-lint-ignore no-explicit-any
export async function handleReferences(ctx: HandlerContext, params: any) {
  const doc = ctx.documents.get(params.textDocument.uri);
  if (!doc) return [];

  try {
    const text = doc.getText();
    const { line, character: char } = params.position;

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
    for (const uri of ctx.workspace.files) {
      if (searched.has(uri)) continue;
      searched.add(uri);
      const otherText = await ctx.workspace.getFileContentAsync(uri);
      if (!otherText) continue;
      try {
        const otherRefs = gleamArray(find_references_to_name(otherText, blueprintName) as GleamList);
        for (const r of otherRefs) {
          crossFileRefs.push({ uri, range: range(r[0], r[1], r[0], r[1] + r[2]) });
        }
      } catch { /* skip */ }
    }

    return [...sameFileRefs, ...crossFileRefs];
  } catch {
    return [];
  }
}

// --- Workspace symbols ---

// deno-lint-ignore no-explicit-any
export async function handleWorkspaceSymbol(ctx: HandlerContext, params: any) {
  const query = (params.query ?? "").toLowerCase();
  // deno-lint-ignore no-explicit-any
  const results: any[] = [];

  for (const uri of ctx.workspace.files) {
    const text = await ctx.workspace.getFileContentAsync(uri);
    if (!text) continue;

    try {
      for (const sym of gleamArray(get_workspace_symbols(text) as GleamList)) {
        if (query && !(sym.name as string).toLowerCase().includes(query)) continue;
        const r = range(sym.line, sym.col, sym.line, sym.col + sym.name_len);
        results.push({ name: sym.name, kind: sym.kind, location: { uri, range: r } });
      }
    } catch { /* ignore */ }
  }

  return results;
}
