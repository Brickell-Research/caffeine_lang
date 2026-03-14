// Graph topology features — custom LSP request handlers for the
// interactive dependency graph webview panel.

import { fileURLToPath } from "node:url";
import type { HandlerContext } from "./handlers.ts";
import { extractPathPrefix } from "./workspace_parsers.ts";
import { debug } from "./debug.ts";

// --- Types ---

interface GraphNode {
  id: string;
  label: string;
  service: string;
  org: string;
  team: string;
  vendor: string | null;
}

interface GraphEdge {
  source: string;
  target: string;
  relationType: "hard" | "soft";
}

interface GraphData {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

interface DependencyEdit {
  action: "add" | "remove";
  source: string;       // dotted ID of the source expectation
  target: string;       // dotted ID of the target expectation
  relationType: "hard" | "soft";
}

// --- Request handlers ---

/** Handle `caffeine/dependencyGraph` — returns the full graph data from workspace indices. */
export function handleDependencyGraph(ctx: HandlerContext): GraphData {
  const nodes: GraphNode[] = [];
  const edges: GraphEdge[] = [];
  const seenNodeIds = new Set<string>();

  // Build nodes from expectation index, edges from dependency index
  for (const [uri, idMap] of ctx.workspace.expectationIndex) {
    let org: string, team: string, service: string;
    try {
      [org, team, service] = extractPathPrefix(fileURLToPath(uri));
    } catch {
      continue;
    }

    const vendorMap = ctx.workspace.vendorIndex.get(uri);
    const depMap = ctx.workspace.dependencyIndex.get(uri);

    for (const [itemName, dottedId] of idMap) {
      if (!seenNodeIds.has(dottedId)) {
        seenNodeIds.add(dottedId);
        nodes.push({
          id: dottedId,
          label: itemName,
          service,
          org,
          team,
          vendor: vendorMap?.get(itemName) ?? ctx.workspace.getVendorForItem(uri, itemName),
        });
      }

      // Add edges from dependency relations
      const deps = depMap?.get(itemName);
      if (deps) {
        for (const target of deps.hard) {
          edges.push({ source: dottedId, target, relationType: "hard" });
        }
        for (const target of deps.soft) {
          edges.push({ source: dottedId, target, relationType: "soft" });
        }
      }
    }
  }

  // Add placeholder nodes for dependency targets not yet in the graph
  for (const edge of edges) {
    if (!seenNodeIds.has(edge.target)) {
      seenNodeIds.add(edge.target);
      const parts = edge.target.split(".");
      nodes.push({
        id: edge.target,
        label: parts[3] ?? edge.target,
        service: parts[2] ?? "unknown",
        org: parts[0] ?? "unknown",
        team: parts[1] ?? "unknown",
        vendor: null,
      });
    }
  }

  debug(`dependencyGraph: ${nodes.length} nodes, ${edges.length} edges`);
  return { nodes, edges };
}

/** Handle `caffeine/applyDependencyEdit` — modifies .caffeine source to add/remove a dependency.
 *  Returns { success: boolean, error?: string }. */
export async function handleApplyDependencyEdit(
  ctx: HandlerContext,
  edit: DependencyEdit,
): Promise<{ success: boolean; error?: string }> {
  // Find the file and item that owns the source expectation
  const sourceItem = findExpectationItem(ctx, edit.source);
  if (!sourceItem) {
    return { success: false, error: `Source expectation "${edit.source}" not found in workspace` };
  }

  const text = await ctx.workspace.getFileContentAsync(sourceItem.uri);
  if (!text) {
    return { success: false, error: `Could not read file for "${edit.source}"` };
  }

  const newText = edit.action === "add"
    ? addDependency(text, sourceItem.itemName, edit.target, edit.relationType)
    : removeDependency(text, sourceItem.itemName, edit.target, edit.relationType);

  if (newText === null) {
    return { success: false, error: `Could not ${edit.action} dependency in source file` };
  }

  if (newText === text) {
    return { success: true }; // No-op: already in desired state
  }

  // Apply via workspace/applyEdit so the client sees the change
  const result = await ctx.connection.workspace.applyEdit({
    label: `${edit.action} ${edit.relationType} dependency: ${edit.target}`,
    edit: {
      changes: {
        [sourceItem.uri]: [{
          range: {
            start: { line: 0, character: 0 },
            end: { line: text.split("\n").length, character: 0 },
          },
          newText,
        }],
      },
    },
  });

  if (!result.applied) {
    return { success: false, error: "Client rejected the edit" };
  }
  return { success: true };
}

// --- Helpers ---

function findExpectationItem(
  ctx: HandlerContext,
  dottedId: string,
): { uri: string; itemName: string } | null {
  for (const [uri, idMap] of ctx.workspace.expectationIndex) {
    for (const [itemName, id] of idMap) {
      if (id === dottedId) return { uri, itemName };
    }
  }
  return null;
}

/** Add a dependency target to a relation list in the item's Provides block. */
function addDependency(
  text: string,
  itemName: string,
  target: string,
  relationType: "hard" | "soft",
): string | null {
  const lines = text.split("\n");
  const itemIdx = findItemLine(lines, itemName);
  if (itemIdx < 0) return null;

  const relationsIdx = findRelationsBlock(lines, itemIdx);
  if (relationsIdx >= 0) {
    // Relations block exists — find or create the relation type list
    return updateRelationList(lines, relationsIdx, relationType, target, "add");
  }

  // No relations block — insert one after the item's Provides opening
  const providesIdx = findProvidesBlock(lines, itemIdx);
  if (providesIdx < 0) return null;

  // Detect indentation from the Provides line
  const indent = lines[providesIdx].match(/^(\s*)/)?.[1] ?? "    ";
  const innerIndent = indent + "  ";
  const otherType = relationType === "hard" ? "soft" : "hard";

  const relationsBlock = [
    `${innerIndent}relations: {`,
    `${innerIndent}  ${relationType}: ["${target}"]`,
    `${innerIndent}  ${otherType}: []`,
    `${innerIndent}}`,
  ];

  // Insert before the closing brace of Provides
  const closingIdx = findBlockClose(lines, providesIdx);
  if (closingIdx < 0) return null;

  lines.splice(closingIdx, 0, ...relationsBlock);
  return lines.join("\n");
}

/** Remove a dependency target from a relation list. */
function removeDependency(
  text: string,
  itemName: string,
  target: string,
  relationType: "hard" | "soft",
): string | null {
  const lines = text.split("\n");
  const itemIdx = findItemLine(lines, itemName);
  if (itemIdx < 0) return null;

  const relationsIdx = findRelationsBlock(lines, itemIdx);
  if (relationsIdx < 0) return text; // No relations block — nothing to remove

  return updateRelationList(lines, relationsIdx, relationType, target, "remove");
}

/** Find the line index of `* "itemName"` */
function findItemLine(lines: string[], itemName: string): number {
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(`"${itemName}"`) && /\*\s+"/.test(lines[i])) {
      return i;
    }
  }
  return -1;
}

/** Find the `relations:` line within an item's Provides block. */
function findRelationsBlock(lines: string[], itemStart: number): number {
  for (let i = itemStart + 1; i < lines.length; i++) {
    // Stop at next item or section header
    if (/^\s*\*\s+"/.test(lines[i])) break;
    if (/^\S/.test(lines[i]) && !lines[i].trim().startsWith("#")) break;
    if (lines[i].trimStart().startsWith("relations:")) return i;
  }
  return -1;
}

/** Find the `Provides` block opening after an item line. */
function findProvidesBlock(lines: string[], itemStart: number): number {
  for (let i = itemStart + 1; i < lines.length; i++) {
    if (/^\s*\*\s+"/.test(lines[i])) break;
    if (/^\S/.test(lines[i]) && !lines[i].trim().startsWith("#")) break;
    if (/Provides\s*\{/.test(lines[i]) || lines[i].trimStart().startsWith("Provides")) return i;
  }
  return -1;
}

/** Find the closing brace of a block starting at `openIdx`. */
function findBlockClose(lines: string[], openIdx: number): number {
  let depth = 0;
  for (let i = openIdx; i < lines.length; i++) {
    for (const ch of lines[i]) {
      if (ch === "{") depth++;
      if (ch === "}") depth--;
      if (depth === 0 && i > openIdx) return i;
    }
  }
  return -1;
}

/** Add or remove a target from a typed relation list within a relations block. */
function updateRelationList(
  lines: string[],
  relationsStart: number,
  relationType: string,
  target: string,
  action: "add" | "remove",
): string | null {
  // Find the end of the relations block
  const relationsEnd = findBlockClose(lines, relationsStart);
  if (relationsEnd < 0) return null;

  // Find the line with `relationType: [...]`
  for (let i = relationsStart; i <= relationsEnd; i++) {
    const typePattern = new RegExp(`${relationType}\\s*:\\s*\\[`);
    if (!typePattern.test(lines[i])) continue;

    // Extract current list content
    const listMatch = lines[i].match(/\[([^\]]*)\]/);
    if (!listMatch) continue;

    const currentItems = listMatch[1]
      .split(",")
      .map((s) => s.trim().replace(/"/g, ""))
      .filter((s) => s.length > 0);

    let newItems: string[];
    if (action === "add") {
      if (currentItems.includes(target)) return lines.join("\n"); // Already present
      newItems = [...currentItems, target];
    } else {
      newItems = currentItems.filter((item) => item !== target);
      if (newItems.length === currentItems.length) return lines.join("\n"); // Not present
    }

    const formatted = newItems.map((item) => `"${item}"`).join(", ");
    lines[i] = lines[i].replace(/\[[^\]]*\]/, `[${formatted}]`);
    return lines.join("\n");
  }

  // relationType list not found in existing relations block
  if (action === "remove") return lines.join("\n"); // Nothing to remove
  // For add: insert a new line for this relation type
  const indent = lines[relationsStart].match(/^(\s*)/)?.[1] ?? "      ";
  const newLine = `${indent}  ${relationType}: ["${target}"]`;
  lines.splice(relationsEnd, 0, newLine);
  return lines.join("\n");
}
