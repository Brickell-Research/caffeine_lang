import * as fs from "node:fs";
import yaml from "js-yaml";
import { Ok, Error, toList } from "../../../prelude.mjs";
import {
  NodeStr,
  NodeInt,
  NodeFloat,
  NodeBool,
  NodeNull,
  NodeSeq,
  NodeMap,
} from "./yaml.mjs";

// Parse YAML file and return list of documents
export function parse_file(path) {
  try {
    const content = fs.readFileSync(path, "utf8");
    const docs = yaml.loadAll(content);
    // Wrap each doc for document_root to unwrap
    const gleamDocs = docs.map((doc) => ({ _yaml_doc: doc }));
    return new Ok(toList(gleamDocs));
  } catch (e) {
    return new Error(e.message || "Failed to parse YAML");
  }
}

// Parse YAML string and return list of documents
export function parse_string(content) {
  try {
    const docs = yaml.loadAll(content);
    const gleamDocs = docs.map((doc) => ({ _yaml_doc: doc }));
    return new Ok(toList(gleamDocs));
  } catch (e) {
    return new Error(e.message || "Failed to parse YAML");
  }
}

// Get root node from document wrapper
export function document_root(doc) {
  return jsToNode(doc._yaml_doc);
}

// Convert JS value to Gleam Node type
function jsToNode(value) {
  if (value === null || value === undefined) {
    return new NodeNull();
  }
  if (typeof value === "string") {
    return new NodeStr(value);
  }
  if (typeof value === "number") {
    if (Number.isInteger(value)) {
      return new NodeInt(value);
    }
    return new NodeFloat(value);
  }
  if (typeof value === "boolean") {
    return new NodeBool(value);
  }
  if (Array.isArray(value)) {
    return new NodeSeq(toList(value.map(jsToNode)));
  }
  if (typeof value === "object") {
    const entries = Object.entries(value).map(([k, v]) => [
      jsToNode(k),
      jsToNode(v),
    ]);
    return new NodeMap(toList(entries));
  }
  return new NodeNull();
}

// Parse integer from string
export function int_parse(s) {
  const n = parseInt(s, 10);
  if (isNaN(n)) {
    return new Error(undefined);
  }
  return new Ok(n);
}

// Pop first grapheme from string
export function pop_grapheme(s) {
  if (s.length === 0) {
    return new Error(undefined);
  }
  // Handle Unicode properly
  const chars = [...s];
  return [chars[0], chars.slice(1).join("")];
}
