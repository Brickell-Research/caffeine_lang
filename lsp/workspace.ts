// Workspace state management — file tracking, blueprint/expectation indices.
// Pure TS/Node logic, no Gleam imports.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { TextDocuments } from "vscode-languageserver/node.js";
import type { TextDocument } from "vscode-languageserver-textdocument";

import {
  extractBlueprintNames,
  extractExpectationIdentifiers,
  findBlueprintItemLocation,
  applyIndexUpdates,
} from "./workspace_parsers.ts";

import { compile_validated_blueprints, Ok, toList } from "./gleam_imports.ts";
import type { GleamList } from "./helpers.ts";
import { gleamArray } from "./helpers.ts";

export class WorkspaceIndex {
  root: string | null = null;
  files = new Set<string>();
  blueprintIndex = new Map<string, Set<string>>();
  expectationIndex = new Map<string, Map<string, string>>();
  // deno-lint-ignore no-explicit-any
  validatedBlueprintsCache = new Map<string, any>();

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
        const names = extractBlueprintNames(text);
        if (names.length > 0) {
          this.blueprintIndex.set(uri, new Set(names));
          this.tryCompileBlueprints(uri, text);
        }
        const ids = extractExpectationIdentifiers(text, uri);
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

  /** Look up a cross-file blueprint definition by blueprint item name. */
  async findCrossFileBlueprintDef(
    blueprintItemName: string,
  ): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
    for (const [uri, names] of this.blueprintIndex) {
      if (!names.has(blueprintItemName)) continue;
      const text = await this.getFileContentAsync(uri);
      if (!text) continue;
      const loc = findBlueprintItemLocation(text, blueprintItemName);
      if (loc) return { uri, ...loc };
    }
    return null;
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
      const loc = findBlueprintItemLocation(text, itemName);
      if (loc) return { uri, ...loc };
    }
    return null;
  }

  /** Updates both blueprint and expectation indices for a file. Returns true if either changed. */
  updateIndicesForFile(uri: string, text: string): boolean {
    const changed = applyIndexUpdates(uri, text, this.blueprintIndex, this.expectationIndex);
    if (this.blueprintIndex.has(uri)) {
      this.tryCompileBlueprints(uri, text);
    } else {
      this.validatedBlueprintsCache.delete(uri);
    }
    return changed;
  }

  /** Try to compile and validate blueprints from file content, caching the result. */
  private tryCompileBlueprints(uri: string, text: string): void {
    try {
      const result = compile_validated_blueprints(text);
      if (result instanceof Ok) {
        this.validatedBlueprintsCache.set(uri, result[0]);
      } else {
        this.validatedBlueprintsCache.delete(uri);
      }
    } catch {
      this.validatedBlueprintsCache.delete(uri);
    }
  }

  /** Collect all validated blueprints across the workspace as a single Gleam list. */
  // deno-lint-ignore no-explicit-any
  allValidatedBlueprints(): any {
    // deno-lint-ignore no-explicit-any
    const all: any[] = [];
    for (const cached of this.validatedBlueprintsCache.values()) {
      all.push(...gleamArray(cached as GleamList));
    }
    return toList(all);
  }
}
