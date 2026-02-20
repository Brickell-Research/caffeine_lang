// Workspace state management — file tracking, blueprint/expectation indices.
// Pure TS/Node logic, no Gleam imports.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { TextDocuments } from "npm:vscode-languageserver/node.js";
import type { TextDocument } from "npm:vscode-languageserver-textdocument";

export class WorkspaceIndex {
  root: string | null = null;
  files = new Set<string>();
  blueprintIndex = new Map<string, Set<string>>();
  expectationIndex = new Map<string, Map<string, string>>();

  private documents: TextDocuments<TextDocument>;

  constructor(documents: TextDocuments<TextDocument>) {
    this.documents = documents;
  }

  /** Initialize from a workspace root URI: scan files and build indices. */
  async initializeFromRoot(rootUri: string): Promise<void> {
    this.root = rootUri.startsWith("file://")
      ? fileURLToPath(rootUri)
      : rootUri;
    await this.scanCaffeineFiles(this.root);

    for (const uri of this.files) {
      const text = await this.getFileContentAsync(uri);
      if (text) {
        const names = WorkspaceIndex.extractBlueprintNames(text);
        if (names.length > 0) {
          this.blueprintIndex.set(uri, new Set(names));
        }
        const ids = WorkspaceIndex.extractExpectationIdentifiers(text, uri);
        if (ids.size > 0) {
          this.expectationIndex.set(uri, ids);
        }
      }
    }
  }

  /** Directories to skip during workspace scanning. */
  private static readonly SKIP_DIRS = new Set([
    "node_modules",
    ".git",
    "build",
    ".claude",
    "dist",
    "vendor",
    ".deno",
  ]);

  /** Recursively find all .caffeine files under a directory. */
  async scanCaffeineFiles(dir: string): Promise<void> {
    let entries: fs.Dirent[];
    try {
      entries = await fs.promises.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!WorkspaceIndex.SKIP_DIRS.has(entry.name)) {
          await this.scanCaffeineFiles(path.join(dir, entry.name));
        }
      } else if (entry.isFile() && entry.name.endsWith(".caffeine")) {
        this.files.add(pathToFileURL(path.join(dir, entry.name)).toString());
      }
    }
  }

  /** Read file content: prefer open document, fall back to async disk read. */
  async getFileContentAsync(uri: string): Promise<string | null> {
    const doc = this.documents.get(uri);
    if (doc) return doc.getText();
    try {
      const filePath = fileURLToPath(uri);
      return await fs.promises.readFile(filePath, "utf-8");
    } catch {
      return null;
    }
  }

  /** Extract blueprint item names from a file's text. Returns empty array for non-blueprint files. */
  static extractBlueprintNames(text: string): string[] {
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

  /** Collect all known blueprint names across the workspace. */
  allKnownBlueprints(): string[] {
    const names: string[] = [];
    for (const set of this.blueprintIndex.values()) {
      for (const name of set) {
        names.push(name);
      }
    }
    return names;
  }

  /** Find the location of a blueprint item (e.g. * "name") within a blueprint file. */
  static findBlueprintItemLocation(
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

  /** Look up a cross-file blueprint definition by blueprint item name. */
  async findCrossFileBlueprintDef(
    blueprintItemName: string,
  ): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
    for (const [uri, names] of this.blueprintIndex) {
      if (!names.has(blueprintItemName)) continue;
      const text = await this.getFileContentAsync(uri);
      if (!text) continue;
      const loc = WorkspaceIndex.findBlueprintItemLocation(text, blueprintItemName);
      if (loc) return { uri, ...loc };
    }
    return null;
  }

  /** Extract org/team/service from a file path (last 3 path segments). */
  static extractPathPrefix(filePath: string): [string, string, string] {
    const segments = filePath.split(path.sep);
    const last3 = segments.slice(-3);
    if (last3.length < 3) return ["unknown", "unknown", "unknown"];
    const [org, team, serviceFile] = last3;
    const service = serviceFile.replace(/\.caffeine$/, "").replace(/\.json$/, "");
    return [org, team, service];
  }

  /** Extract expectation identifiers (org.team.service.name) from an expects file. */
  static extractExpectationIdentifiers(
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
    const [org, team, service] = WorkspaceIndex.extractPathPrefix(filePath);

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

  /** Collect all known expectation dotted identifiers across the workspace. */
  allKnownExpectationIdentifiers(): string[] {
    const ids: string[] = [];
    for (const idMap of this.expectationIndex.values()) {
      for (const dottedId of idMap.values()) {
        ids.push(dottedId);
      }
    }
    return ids;
  }

  /** Look up an expectation definition by dotted identifier. */
  async findExpectationByIdentifier(
    dottedId: string,
  ): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
    const parts = dottedId.split(".");
    if (parts.length !== 4) return null;
    const itemName = parts[3];

    for (const [uri, idMap] of this.expectationIndex) {
      if (idMap.get(itemName) !== dottedId) continue;
      const text = await this.getFileContentAsync(uri);
      if (!text) continue;
      const loc = WorkspaceIndex.findBlueprintItemLocation(text, itemName);
      if (loc) return { uri, ...loc };
    }
    return null;
  }

  /** Updates both blueprint and expectation indices for a file. Returns true if either changed. */
  updateIndicesForFile(uri: string, text: string): boolean {
    let changed = false;

    const newNames = WorkspaceIndex.extractBlueprintNames(text);
    const oldNames = this.blueprintIndex.get(uri);
    if (newNames.length > 0) {
      this.blueprintIndex.set(uri, new Set(newNames));
    } else {
      this.blueprintIndex.delete(uri);
    }
    const namesChanged = !oldNames
      || oldNames.size !== newNames.length
      || newNames.some((n) => !oldNames.has(n));
    if ((namesChanged && newNames.length > 0) || (oldNames && newNames.length === 0)) {
      changed = true;
    }

    const newIds = WorkspaceIndex.extractExpectationIdentifiers(text, uri);
    const oldIds = this.expectationIndex.get(uri);
    if (newIds.size > 0) {
      this.expectationIndex.set(uri, newIds);
    } else {
      this.expectationIndex.delete(uri);
    }
    const idsChanged = !oldIds
      || oldIds.size !== newIds.size
      || [...newIds.entries()].some(([k, v]) => oldIds.get(k) !== v);
    if ((idsChanged && newIds.size > 0) || (oldIds && newIds.size === 0)) {
      changed = true;
    }

    return changed;
  }
}
