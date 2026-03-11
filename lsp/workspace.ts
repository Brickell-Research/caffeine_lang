// Workspace state management — file tracking, blueprint/expectation indices.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { TextDocuments } from "vscode-languageserver/node.js";
import type { TextDocument } from "vscode-languageserver-textdocument";

import {
  extractBlueprintNames,
  extractReferencedBlueprintNames,
  extractExpectationIdentifiers,
  extractVendors,
  findBlueprintItemLocation,
  applyIndexUpdates,
} from "./workspace_parsers.ts";

import { compile_validated_blueprints, get_workspace_symbols, Ok, toList } from "./gleam_imports.ts";
import type { GleamList } from "./helpers.ts";
import { gleamArray } from "./helpers.ts";
import { debug } from "./debug.ts";

export class WorkspaceIndex {
  root: string | null = null;
  files = new Set<string>();
  blueprintIndex = new Map<string, Set<string>>();
  referencedBlueprintIndex = new Map<string, Set<string>>();
  expectationIndex = new Map<string, Map<string, string>>();
  /** Maps file URI → (item name → vendor string, e.g., "datadog").
   *  Covers both blueprint items and expectation items that have vendor in Provides. */
  vendorIndex = new Map<string, Map<string, string>>();
  // deno-lint-ignore no-explicit-any
  validatedBlueprintsCache = new Map<string, any>();
  // deno-lint-ignore no-explicit-any
  private _mergedValidatedBlueprints: any = null;
  private _validatedBlueprintsDirty = true;

  /** Cached workspace symbols per file URI. */
  // deno-lint-ignore no-explicit-any
  private workspaceSymbolsCache = new Map<string, any[]>();

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
        const refBlueprints = extractReferencedBlueprintNames(text);
        if (refBlueprints.length > 0) {
          this.referencedBlueprintIndex.set(uri, new Set(refBlueprints));
        }
        const ids = extractExpectationIdentifiers(text, uri);
        if (ids.size > 0) {
          this.expectationIndex.set(uri, ids);
        }
        const vendors = extractVendors(text);
        if (vendors.size > 0) {
          this.vendorIndex.set(uri, vendors);
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

  /** Collect all referenced blueprint names across the workspace (from expects files). */
  allReferencedBlueprints(): string[] {
    const names: string[] = [];
    for (const set of this.referencedBlueprintIndex.values()) {
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

  /** Updates blueprint, expectation, and referenced blueprint indices for a file. Returns true if any changed. */
  updateIndicesForFile(uri: string, text: string): boolean {
    const changed = applyIndexUpdates(uri, text, this.blueprintIndex, this.expectationIndex);
    this.workspaceSymbolsCache.delete(uri);
    if (this.blueprintIndex.has(uri)) {
      this.tryCompileBlueprints(uri, text);
    } else if (this.validatedBlueprintsCache.delete(uri)) {
      this._validatedBlueprintsDirty = true;
    }
    // Update referenced blueprint index
    const newRefs = extractReferencedBlueprintNames(text);
    if (newRefs.length > 0) {
      this.referencedBlueprintIndex.set(uri, new Set(newRefs));
    } else {
      this.referencedBlueprintIndex.delete(uri);
    }
    // Update vendor index
    const newVendors = extractVendors(text);
    if (newVendors.size > 0) {
      this.vendorIndex.set(uri, newVendors);
    } else {
      this.vendorIndex.delete(uri);
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
    this._validatedBlueprintsDirty = true;
  }

  /** Remove a file from all indices. Returns true if any index was modified. */
  removeFile(uri: string): boolean {
    this.files.delete(uri);
    this.workspaceSymbolsCache.delete(uri);
    const hadBlueprints = this.blueprintIndex.delete(uri);
    const hadRefs = this.referencedBlueprintIndex.delete(uri);
    const hadExpectations = this.expectationIndex.delete(uri);
    this.vendorIndex.delete(uri);
    if (this.validatedBlueprintsCache.delete(uri)) {
      this._validatedBlueprintsDirty = true;
    }
    return hadBlueprints || hadRefs || hadExpectations;
  }

  /** Collect all validated blueprints across the workspace as a single Gleam list. */
  // deno-lint-ignore no-explicit-any
  allValidatedBlueprints(): any {
    if (!this._validatedBlueprintsDirty && this._mergedValidatedBlueprints) {
      return this._mergedValidatedBlueprints;
    }
    // deno-lint-ignore no-explicit-any
    const all: any[] = [];
    for (const cached of this.validatedBlueprintsCache.values()) {
      all.push(...gleamArray(cached as GleamList));
    }
    this._mergedValidatedBlueprints = toList(all);
    this._validatedBlueprintsDirty = false;
    return this._mergedValidatedBlueprints;
  }

  /** Check whether any expectation in the workspace uses a given vendor. */
  hasVendor(vendor: string): boolean {
    for (const vendorMap of this.vendorIndex.values()) {
      for (const v of vendorMap.values()) {
        if (v === vendor) return true;
      }
    }
    return false;
  }

  /** Get the vendor for an expectation item in a file, or null.
   *  First checks if the expectation itself provides a vendor,
   *  then resolves through its blueprint. */
  getVendorForItem(uri: string, itemName: string): string | null {
    // Direct vendor in expectation's Provides
    const direct = this.vendorIndex.get(uri)?.get(itemName);
    if (direct) return direct;

    // Resolve through blueprint: find which blueprint this expectation references
    const text = this.documents.get(uri)?.getText();
    if (!text) return null;
    const blueprintName = this.findBlueprintForExpectation(text, itemName);
    if (!blueprintName) return null;

    // Look up the vendor from the blueprint's vendor index
    for (const [bpUri, vendors] of this.vendorIndex) {
      if (!this.blueprintIndex.has(bpUri)) continue;
      const vendor = vendors.get(blueprintName);
      if (vendor) return vendor;
    }
    return null;
  }

  /** Find the blueprint name referenced by an expectation item.
   *  Looks for the nearest `Expectations for "name"` header above the item. */
  private findBlueprintForExpectation(text: string, itemName: string): string | null {
    const lines = text.split("\n");
    const headerPattern = /Expectations\s+for\s+"([^"]+)"/;
    let currentBlueprint: string | null = null;
    for (const line of lines) {
      const headerMatch = headerPattern.exec(line);
      if (headerMatch) {
        currentBlueprint = headerMatch[1];
      }
      if (currentBlueprint && line.includes(`"${itemName}"`)) {
        return currentBlueprint;
      }
    }
    return null;
  }

  /** Get the dotted identifier for an expectation item in a file, or null. */
  getDottedIdForItem(uri: string, itemName: string): string | null {
    return this.expectationIndex.get(uri)?.get(itemName) ?? null;
  }

  /** Get cached workspace symbols for a file, computing on first access. */
  // deno-lint-ignore no-explicit-any
  getCachedWorkspaceSymbols(uri: string, text: string): any[] {
    const cached = this.workspaceSymbolsCache.get(uri);
    if (cached) return cached;

    try {
      const symbols = gleamArray(get_workspace_symbols(text) as GleamList);
      this.workspaceSymbolsCache.set(uri, symbols);
      return symbols;
    } catch (e) {
      debug(`getCachedWorkspaceSymbols(${uri}): ${e}`);
      return [];
    }
  }
}
