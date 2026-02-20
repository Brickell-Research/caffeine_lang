// Pure parsing utilities for Caffeine workspace files.
// Stateless functions for extracting blueprint names, expectation identifiers,
// and locating items within file text.

import path from "node:path";
import { fileURLToPath } from "node:url";

/** Extract blueprint item names from a file's text. Returns empty array for non-blueprint files. */
export function extractBlueprintNames(text: string): string[] {
  if (!text.includes("Blueprints for")) return [];
  const names: string[] = [];
  const pattern = /\*\s+"([^"]+)"/;
  for (const line of text.split("\n")) {
    if (line.trimStart().startsWith("#")) continue;
    const match = pattern.exec(line);
    if (match) names.push(match[1]);
  }
  return names;
}

/** Find the location of a blueprint item (e.g. * "name") within a blueprint file. */
export function findBlueprintItemLocation(
  text: string,
  itemName: string,
): { line: number; col: number; nameLen: number } | null {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (!/^\s*\*\s+"/.test(lines[i])) continue;
    const nameIdx = lines[i].indexOf(`"${itemName}"`);
    if (nameIdx < 0) continue;
    return { line: i, col: nameIdx + 1, nameLen: itemName.length };
  }
  return null;
}

/** Extract org/team/service from a file path (last 3 path segments). */
export function extractPathPrefix(filePath: string): [string, string, string] {
  const segments = filePath.split(path.sep);
  const last3 = segments.slice(-3);
  if (last3.length < 3) return ["unknown", "unknown", "unknown"];
  const [org, team, serviceFile] = last3;
  const service = serviceFile.replace(/\.caffeine$/, "").replace(/\.json$/, "");
  return [org, team, service];
}

/** Extract expectation identifiers (org.team.service.name) from an expects file. */
export function extractExpectationIdentifiers(
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

/** Update blueprint and expectation indices for a file, mutating both maps in place. Returns true if either changed. */
export function applyIndexUpdates(
  uri: string,
  text: string,
  blueprintIndex: Map<string, Set<string>>,
  expectationIndex: Map<string, Map<string, string>>,
): boolean {
  let changed = false;

  const newNames = extractBlueprintNames(text);
  const oldNames = blueprintIndex.get(uri);
  const namesChanged = !oldNames
    || oldNames.size !== newNames.length
    || newNames.some((n) => !oldNames.has(n));
  if ((namesChanged && newNames.length > 0) || (oldNames && newNames.length === 0)) {
    changed = true;
  }
  if (newNames.length > 0) {
    blueprintIndex.set(uri, new Set(newNames));
  } else {
    blueprintIndex.delete(uri);
  }

  const newIds = extractExpectationIdentifiers(text, uri);
  const oldIds = expectationIndex.get(uri);
  const idsChanged = !oldIds
    || oldIds.size !== newIds.size
    || [...newIds.entries()].some(([k, v]) => oldIds.get(k) !== v);
  if ((idsChanged && newIds.size > 0) || (oldIds && newIds.size === 0)) {
    changed = true;
  }
  if (newIds.size > 0) {
    expectationIndex.set(uri, newIds);
  } else {
    expectationIndex.delete(uri);
  }

  return changed;
}
