/// Minimal YAML parser abstraction that works on both Erlang and JavaScript targets.
/// On Erlang, delegates to glaml. On JavaScript, uses js-yaml via FFI.

import gleam/string

/// YAML node types matching glaml's structure
pub type Node {
  NodeStr(String)
  NodeInt(Int)
  NodeFloat(Float)
  NodeBool(Bool)
  NodeNull
  NodeSeq(List(Node))
  NodeMap(List(#(Node, Node)))
}

/// Opaque document type
pub type Doc

/// Parse a YAML file from disk
@external(erlang, "yaml_ffi", "parse_file")
@external(javascript, "./yaml_ffi.mjs", "parse_file")
pub fn parse_file(path: String) -> Result(List(Doc), String)

/// Parse a YAML string
@external(erlang, "yaml_ffi", "parse_string")
@external(javascript, "./yaml_ffi.mjs", "parse_string")
pub fn parse_string(content: String) -> Result(List(Doc), String)

/// Get the root node from a document
@external(erlang, "yaml_ffi", "document_root")
@external(javascript, "./yaml_ffi.mjs", "document_root")
pub fn document_root(doc: Doc) -> Node

/// Navigate YAML structure using glaml-style sugar syntax
/// Supports: "key" for map access, "#0" for list index
pub fn select_sugar(node: Node, path: String) -> Result(Node, Nil) {
  case path {
    "" -> Ok(node)
    "#" <> rest -> {
      let #(idx_str, remaining) = split_at_dot(rest)
      case int_parse(idx_str) {
        Ok(idx) -> {
          case node {
            NodeSeq(items) -> {
              case list_at(items, idx) {
                Ok(item) -> select_sugar(item, remaining)
                Error(_) -> Error(Nil)
              }
            }
            _ -> Error(Nil)
          }
        }
        Error(_) -> Error(Nil)
      }
    }
    _ -> {
      let #(key, remaining) = split_at_dot(path)
      case node {
        NodeMap(entries) -> {
          case find_in_map(entries, key) {
            Ok(value) -> select_sugar(value, remaining)
            Error(_) -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }
  }
}

fn split_at_dot(s: String) -> #(String, String) {
  case string.split_once(s, ".") {
    Ok(#(before, after)) -> #(before, after)
    Error(_) -> #(s, "")
  }
}

fn find_in_map(
  entries: List(#(Node, Node)),
  key: String,
) -> Result(Node, Nil) {
  case entries {
    [] -> Error(Nil)
    [#(NodeStr(k), v), ..] if k == key -> Ok(v)
    [_, ..rest] -> find_in_map(rest, key)
  }
}

fn list_at(items: List(a), index: Int) -> Result(a, Nil) {
  case items, index {
    [item, ..], 0 -> Ok(item)
    [_, ..rest], n if n > 0 -> list_at(rest, n - 1)
    _, _ -> Error(Nil)
  }
}

@external(erlang, "yaml_ffi", "int_parse")
@external(javascript, "./yaml_ffi.mjs", "int_parse")
fn int_parse(s: String) -> Result(Int, Nil)
