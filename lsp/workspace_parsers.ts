// Pure parsing utilities for Caffeine workspace files.
// Stateless functions for extracting measurement names, expectation identifiers,
// and locating items within file text.

import path from "node:path";
import { fileURLToPath } from "node:url";

/** Extract measurement item names from a file's text. Returns empty array for non-measurement files.
 *  Measurement items start with `"name":` at column 0 (no `*` prefix).
 *  Non-expectations files are measurement files. */
export function extractMeasurementNames(text: string): string[] {
  if (text.includes("Expectations")) return [];
  const names: string[] = [];
  const pattern = /^"([^"]+)"\s*(?:extends\s*\[|:)/;
  for (const line of text.split("\n")) {
    if (line.trimStart().startsWith("#")) continue;
    const match = pattern.exec(line);
    if (match) names.push(match[1]);
  }
  return names;
}

/** Find the location of a measurement item (e.g. "name":) within a measurement file.
 *  Measurement items start with `"name":` at column 0. */
export function findMeasurementItemLocation(
  text: string,
  itemName: string,
): { line: number; col: number; nameLen: number } | null {
  const lines = text.split("\n");
  const pattern = /^"([^"]+)"\s*(?:extends\s*\[|:)/;
  for (let i = 0; i < lines.length; i++) {
    if (!pattern.test(lines[i])) continue;
    const nameIdx = lines[i].indexOf(`"${itemName}"`);
    if (nameIdx < 0) continue;
    return { line: i, col: nameIdx + 1, nameLen: itemName.length };
  }
  return null;
}

/** Extract measurement names referenced via `Expectations measured by "name"` headers. */
export function extractReferencedMeasurementNames(text: string): string[] {
  const names: string[] = [];
  const pattern = /Expectations\s+measured\s+by\s+"([^"]+)"/;
  for (const line of text.split("\n")) {
    if (line.trimStart().startsWith("#")) continue;
    const match = pattern.exec(line);
    if (match) names.push(match[1]);
  }
  return names;
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
  if (!text.includes("Expectations measured by")) return result;

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
      const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
      result.set(name, `${org}.${team}.${service}.${slug}`);
    }
  }
  return result;
}

/** Known vendor names that can appear as measurement filename stems. */
const KNOWN_VENDORS = new Set(["datadog", "honeycomb", "dynatrace", "newrelic"]);

/** Derive vendor for measurement items from the filename stem.
 *  Measurement files are named after their vendor (e.g., datadog.caffeine).
 *  Extracts item names from the file and maps each to the vendor derived
 *  from the filename. Returns an empty map for non-measurement files or
 *  when the filename stem is not a known vendor. */
export function extractVendors(text: string, uri?: string): Map<string, string> {
  const result = new Map<string, string>();
  if (!uri) return result;

  // Derive vendor from filename stem
  const filename = uri.split("/").pop() ?? "";
  const stem = filename.replace(/\.caffeine$/, "");
  if (!KNOWN_VENDORS.has(stem)) return result;

  // Map each measurement item to the derived vendor
  const names = extractMeasurementNames(text);
  for (const name of names) {
    result.set(name, stem);
  }

  return result;
}

/** Update measurement and expectation indices for a file, mutating both maps in place. Returns true if either changed. */
export function applyIndexUpdates(
  uri: string,
  text: string,
  measurementIndex: Map<string, Set<string>>,
  expectationIndex: Map<string, Map<string, string>>,
): boolean {
  let changed = false;

  const newNames = extractMeasurementNames(text);
  const oldNames = measurementIndex.get(uri);
  const namesChanged = !oldNames
    || oldNames.size !== newNames.length
    || newNames.some((n) => !oldNames.has(n));
  if ((namesChanged && newNames.length > 0) || (oldNames && newNames.length === 0)) {
    changed = true;
  }
  if (newNames.length > 0) {
    measurementIndex.set(uri, new Set(newNames));
  } else {
    measurementIndex.delete(uri);
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
