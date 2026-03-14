// Workspace state management — file tracking, measurement/expectation indices.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { TextDocuments } from "vscode-languageserver/node.js";
import type { TextDocument } from "vscode-languageserver-textdocument";

import {
  extractMeasurementNames,
  extractReferencedMeasurementNames,
  extractExpectationIdentifiers,
  extractVendors,
  findMeasurementItemLocation,
  applyIndexUpdates,
} from "./workspace_parsers.ts";

import { compile_validated_measurements, get_workspace_symbols, Ok, toList } from "./gleam_imports.ts";
import type { GleamList } from "./helpers.ts";
import { gleamArray } from "./helpers.ts";
import { debug } from "./debug.ts";

export class WorkspaceIndex {
  root: string | null = null;
  files = new Set<string>();
  measurementIndex = new Map<string, Set<string>>();
  referencedMeasurementIndex = new Map<string, Set<string>>();
  expectationIndex = new Map<string, Map<string, string>>();
  /** Maps file URI → (item name → vendor string, e.g., "datadog").
   *  Derived from measurement filenames (e.g., datadog.caffeine → "datadog"). */
  vendorIndex = new Map<string, Map<string, string>>();
  // deno-lint-ignore no-explicit-any
  validatedMeasurementsCache = new Map<string, any>();
  // deno-lint-ignore no-explicit-any
  private _mergedValidatedMeasurements: any = null;
  private _validatedMeasurementsDirty = true;

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
        const names = extractMeasurementNames(text);
        if (names.length > 0) {
          this.measurementIndex.set(uri, new Set(names));
          this.tryCompileMeasurements(uri, text);
        }
        const refMeasurements = extractReferencedMeasurementNames(text);
        if (refMeasurements.length > 0) {
          this.referencedMeasurementIndex.set(uri, new Set(refMeasurements));
        }
        const ids = extractExpectationIdentifiers(text, uri);
        if (ids.size > 0) {
          this.expectationIndex.set(uri, ids);
        }
        const vendors = extractVendors(text, uri);
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

  /** Collect all known measurement names across the workspace. */
  allKnownMeasurements(): string[] {
    const names: string[] = [];
    for (const set of this.measurementIndex.values()) {
      for (const name of set) {
        names.push(name);
      }
    }
    return names;
  }

  /** Collect all referenced measurement names across the workspace (from expects files). */
  allReferencedMeasurements(): string[] {
    const names: string[] = [];
    for (const set of this.referencedMeasurementIndex.values()) {
      for (const name of set) {
        names.push(name);
      }
    }
    return names;
  }

  /** Look up a cross-file measurement definition by measurement item name. */
  async findCrossFileMeasurementDef(
    measurementItemName: string,
  ): Promise<{ uri: string; line: number; col: number; nameLen: number } | null> {
    for (const [uri, names] of this.measurementIndex) {
      if (!names.has(measurementItemName)) continue;
      const text = await this.getFileContentAsync(uri);
      if (!text) continue;
      const loc = findMeasurementItemLocation(text, measurementItemName);
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
      const loc = findMeasurementItemLocation(text, itemName);
      if (loc) return { uri, ...loc };
    }
    return null;
  }

  /** Updates measurement, expectation, and referenced measurement indices for a file. Returns true if any changed. */
  updateIndicesForFile(uri: string, text: string): boolean {
    const changed = applyIndexUpdates(uri, text, this.measurementIndex, this.expectationIndex);
    this.workspaceSymbolsCache.delete(uri);
    if (this.measurementIndex.has(uri)) {
      this.tryCompileMeasurements(uri, text);
    } else if (this.validatedMeasurementsCache.delete(uri)) {
      this._validatedMeasurementsDirty = true;
    }
    // Update referenced measurement index
    const newRefs = extractReferencedMeasurementNames(text);
    if (newRefs.length > 0) {
      this.referencedMeasurementIndex.set(uri, new Set(newRefs));
    } else {
      this.referencedMeasurementIndex.delete(uri);
    }
    // Update vendor index
    const newVendors = extractVendors(text, uri);
    if (newVendors.size > 0) {
      this.vendorIndex.set(uri, newVendors);
    } else {
      this.vendorIndex.delete(uri);
    }
    return changed;
  }

  /** Try to compile and validate measurements from file content, caching the result. */
  private tryCompileMeasurements(uri: string, text: string): void {
    try {
      const result = compile_validated_measurements(text);
      if (result instanceof Ok) {
        this.validatedMeasurementsCache.set(uri, result[0]);
      } else {
        this.validatedMeasurementsCache.delete(uri);
      }
    } catch {
      this.validatedMeasurementsCache.delete(uri);
    }
    this._validatedMeasurementsDirty = true;
  }

  /** Remove a file from all indices. Returns true if any index was modified. */
  removeFile(uri: string): boolean {
    this.files.delete(uri);
    this.workspaceSymbolsCache.delete(uri);
    const hadMeasurements = this.measurementIndex.delete(uri);
    const hadRefs = this.referencedMeasurementIndex.delete(uri);
    const hadExpectations = this.expectationIndex.delete(uri);
    this.vendorIndex.delete(uri);
    if (this.validatedMeasurementsCache.delete(uri)) {
      this._validatedMeasurementsDirty = true;
    }
    return hadMeasurements || hadRefs || hadExpectations;
  }

  /** Collect all validated measurements across the workspace as a single Gleam list. */
  // deno-lint-ignore no-explicit-any
  allValidatedMeasurements(): any {
    if (!this._validatedMeasurementsDirty && this._mergedValidatedMeasurements) {
      return this._mergedValidatedMeasurements;
    }
    // deno-lint-ignore no-explicit-any
    const all: any[] = [];
    for (const cached of this.validatedMeasurementsCache.values()) {
      all.push(...gleamArray(cached as GleamList));
    }
    this._mergedValidatedMeasurements = toList(all);
    this._validatedMeasurementsDirty = false;
    return this._mergedValidatedMeasurements;
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

  /** Get the vendor for an item in a file, or null.
   *  For measurement items, looks up the vendor directly from the vendor index.
   *  For expectation items, resolves through the referenced measurement. */
  getVendorForItem(uri: string, itemName: string): string | null {
    // Direct vendor from measurement file's vendor index
    const direct = this.vendorIndex.get(uri)?.get(itemName);
    if (direct) return direct;

    // Resolve through measurement: find which measurement this expectation references
    const text = this.documents.get(uri)?.getText();
    if (!text) return null;
    const measurementName = this.findMeasurementForExpectation(text, itemName);
    if (!measurementName) return null;

    // Look up the vendor from the measurement's vendor index
    for (const [bpUri, vendors] of this.vendorIndex) {
      if (!this.measurementIndex.has(bpUri)) continue;
      const vendor = vendors.get(measurementName);
      if (vendor) return vendor;
    }
    return null;
  }

  /** Find the measurement name referenced by an expectation item.
   *  Looks for the nearest `Expectations measured by "name"` header above the item. */
  private findMeasurementForExpectation(text: string, itemName: string): string | null {
    const lines = text.split("\n");
    const headerPattern = /Expectations\s+measured\s+by\s+"([^"]+)"/;
    let currentMeasurement: string | null = null;
    for (const line of lines) {
      const headerMatch = headerPattern.exec(line);
      if (headerMatch) {
        currentMeasurement = headerMatch[1];
      }
      if (currentMeasurement && line.includes(`"${itemName}"`)) {
        return currentMeasurement;
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
