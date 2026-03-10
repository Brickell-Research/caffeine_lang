/// LSP request router — single-document and cross-file feature handlers.
import caffeine_lang/frontend/formatter
import caffeine_lsp/code_actions.{ActionDiagnostic}
import caffeine_lsp/completion
import caffeine_lsp/definition
import caffeine_lsp/diagnostics.{
  type DiagnosticCode, BlueprintNotFound, DeadBlueprint, DependencyNotFound,
  MissingRequiredFields, NoDiagnosticCode, QuotedFieldName, TypeMismatch,
  UnknownField, UnusedExtendable, UnusedTypeAlias,
}
import caffeine_lsp/document_symbols
import caffeine_lsp/folding_range
import caffeine_lsp/highlight
import caffeine_lsp/hover
import caffeine_lsp/inlay_hints
import caffeine_lsp/linked_editing_range
import caffeine_lsp/references
import caffeine_lsp/rename
import caffeine_lsp/selection_range
import caffeine_lsp/semantic_tokens
import caffeine_lsp/server/capabilities
import caffeine_lsp/server/params
import caffeine_lsp/server/responses
import caffeine_lsp/server/workspace.{type WorkspaceState}
import caffeine_lsp/signature_help
import caffeine_lsp/type_hierarchy
import caffeine_lsp/workspace_symbols
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/list
import gleam/option
import gleam/string

/// Result of handling a request — includes possibly updated workspace state.
pub type HandleResult {
  HandleResult(workspace: WorkspaceState, response: json.Json)
}

/// Route an LSP request method to the appropriate handler.
/// Returns Error(Nil) for unrecognized methods.
pub fn handle_request(
  method: String,
  params: Dynamic,
  ws: WorkspaceState,
) -> Result(HandleResult, Nil) {
  case method {
    "initialize" -> Ok(handle_initialize(ws, params))
    "textDocument/hover" -> Ok(handle_hover(ws, params))
    "textDocument/completion" -> Ok(handle_completion(ws, params))
    "textDocument/signatureHelp" -> Ok(handle_signature_help(ws, params))
    "textDocument/documentHighlight" -> Ok(handle_highlight(ws, params))
    "textDocument/formatting" -> Ok(handle_formatting(ws, params))
    "textDocument/codeAction" -> Ok(handle_code_action(ws, params))
    "textDocument/prepareRename" -> Ok(handle_prepare_rename(ws, params))
    "textDocument/rename" -> Ok(handle_rename(ws, params))
    "textDocument/documentSymbol" -> Ok(handle_document_symbol(ws, params))
    "textDocument/semanticTokens/full" -> Ok(handle_semantic_tokens(ws, params))
    "textDocument/foldingRange" -> Ok(handle_folding_ranges(ws, params))
    "textDocument/selectionRange" -> Ok(handle_selection_ranges(ws, params))
    "textDocument/linkedEditingRange" -> Ok(handle_linked_editing(ws, params))
    "textDocument/inlayHint" -> Ok(handle_inlay_hints(ws, params))
    "textDocument/definition" -> Ok(handle_definition(ws, params))
    "textDocument/declaration" -> Ok(handle_definition(ws, params))
    "textDocument/references" -> Ok(handle_references(ws, params))
    "workspace/symbol" -> Ok(handle_workspace_symbol(ws, params))
    "textDocument/typeHierarchy/prepare" ->
      Ok(handle_type_hierarchy_prepare(ws, params))
    "typeHierarchy/supertypes" ->
      Ok(handle_type_hierarchy_supertypes(ws, params))
    "typeHierarchy/subtypes" -> Ok(handle_type_hierarchy_subtypes(ws, params))
    "shutdown" -> Ok(HandleResult(ws, json.null()))
    _ -> Error(Nil)
  }
}

// --- Handlers ---

fn handle_hover(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(_, text)) -> {
      let #(ws2, blueprints) = workspace.all_validated_blueprints(ws)
      case params.position(params) {
        Ok(#(line, character)) ->
          case hover.get_hover(text, line, character, blueprints) {
            option.Some(markdown) ->
              HandleResult(ws2, responses.encode_hover(markdown))
            option.None -> HandleResult(ws2, json.null())
          }
        Error(_) -> HandleResult(ws2, json.null())
      }
    }
  }
}

fn handle_completion(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.preprocessed_array([]))
    Ok(#(_, text)) -> {
      let #(ws2, blueprints) = workspace.all_validated_blueprints(ws)
      let blueprint_names = workspace.all_known_blueprints(ws2)
      case params.position(params) {
        Ok(#(line, character)) -> {
          let items =
            completion.get_completions(
              text,
              line,
              character,
              blueprint_names,
              blueprints,
            )
          HandleResult(ws2, responses.encode_completion_items(items))
        }
        Error(_) -> HandleResult(ws2, json.preprocessed_array([]))
      }
    }
  }
}

fn handle_signature_help(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(_, text)) -> {
      let #(ws2, blueprints) = workspace.all_validated_blueprints(ws)
      case params.position(params) {
        Ok(#(line, character)) ->
          case
            signature_help.get_signature_help(text, line, character, blueprints)
          {
            option.Some(sig) ->
              HandleResult(ws2, responses.encode_signature_help(sig))
            option.None -> HandleResult(ws2, json.null())
          }
        Error(_) -> HandleResult(ws2, json.null())
      }
    }
  }
}

fn handle_highlight(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) ->
      case params.position(params) {
        Ok(#(line, character)) -> {
          let highlights = highlight.get_highlights(text, line, character)
          HandleResult(ws, responses.encode_highlights(highlights))
        }
        Error(_) -> empty
      }
  }
}

fn handle_formatting(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) ->
      case formatter.format(text) {
        Ok(formatted) -> {
          let line_count = list.length(string.split(text, "\n"))
          HandleResult(ws, responses.encode_formatting(formatted, line_count))
        }
        Error(_) -> empty
      }
  }
}

fn handle_code_action(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case params.uri(params), params.code_action_diagnostics(params) {
    Ok(uri), Ok(diag_params) -> {
      let gleam_diags =
        list.map(diag_params, fn(d) {
          ActionDiagnostic(
            line: d.start_line,
            character: d.start_character,
            end_line: d.end_line,
            end_character: d.end_character,
            message: d.message,
            code: string_to_diagnostic_code(d.code),
          )
        })
      let actions = code_actions.get_code_actions(gleam_diags, uri)
      HandleResult(ws, responses.encode_code_actions(actions))
    }
    _, _ -> empty
  }
}

fn handle_prepare_rename(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(_, text)) ->
      case params.position(params) {
        Ok(#(line, character)) ->
          case rename.prepare_rename(text, line, character) {
            option.Some(#(r_line, r_col, r_len)) -> {
              let placeholder = extract_text_at(text, r_line, r_col, r_len)
              HandleResult(
                ws,
                responses.encode_prepare_rename(
                  r_line,
                  r_col,
                  r_len,
                  placeholder,
                ),
              )
            }
            option.None -> HandleResult(ws, json.null())
          }
        Error(_) -> HandleResult(ws, json.null())
      }
  }
}

fn handle_rename(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(uri, text)) ->
      case params.position(params), params.new_name(params) {
        Ok(#(line, character)), Ok(new_name) -> {
          let edits = rename.get_rename_edits(text, line, character)
          case edits {
            [] -> HandleResult(ws, json.null())
            _ ->
              HandleResult(
                ws,
                responses.encode_rename_edits(uri, edits, new_name),
              )
          }
        }
        _, _ -> HandleResult(ws, json.null())
      }
  }
}

fn handle_document_symbol(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) -> {
      let symbols = document_symbols.get_symbols(text)
      HandleResult(ws, responses.encode_document_symbols(symbols))
    }
  }
}

fn handle_semantic_tokens(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, responses.encode_semantic_tokens([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) -> {
      let data = semantic_tokens.get_semantic_tokens(text)
      HandleResult(ws, responses.encode_semantic_tokens(data))
    }
  }
}

fn handle_folding_ranges(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) -> {
      let ranges = folding_range.get_folding_ranges(text)
      HandleResult(ws, responses.encode_folding_ranges(ranges))
    }
  }
}

fn handle_selection_ranges(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) ->
      case params.positions(params) {
        Ok(positions) -> {
          let ranges =
            list.map(positions, fn(pos) {
              let #(line, character) = pos
              selection_range.get_selection_range(text, line, character)
            })
          HandleResult(
            ws,
            json.preprocessed_array(list.map(
              ranges,
              responses.encode_selection_range,
            )),
          )
        }
        Error(_) -> empty
      }
  }
}

fn handle_linked_editing(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(_, text)) ->
      case params.position(params) {
        Ok(#(line, character)) -> {
          let ranges =
            linked_editing_range.get_linked_editing_ranges(
              text,
              line,
              character,
            )
          case ranges {
            [] -> HandleResult(ws, json.null())
            _ ->
              HandleResult(ws, responses.encode_linked_editing_ranges(ranges))
          }
        }
        Error(_) -> HandleResult(ws, json.null())
      }
  }
}

fn handle_inlay_hints(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(_, text)) -> {
      let #(ws2, blueprints) = workspace.all_validated_blueprints(ws)
      case params.line_range(params) {
        Ok(#(start_line, end_line)) -> {
          let hints =
            inlay_hints.get_inlay_hints(text, start_line, end_line, blueprints)
          HandleResult(ws2, responses.encode_inlay_hints(hints))
        }
        Error(_) -> HandleResult(ws2, json.preprocessed_array([]))
      }
    }
  }
}

fn handle_type_hierarchy_prepare(
  ws: WorkspaceState,
  params: Dynamic,
) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(uri, text)) ->
      case params.position(params) {
        Ok(#(line, character)) -> {
          let items =
            type_hierarchy.prepare_type_hierarchy(text, line, character)
          case items {
            [] -> HandleResult(ws, json.null())
            _ ->
              HandleResult(
                ws,
                responses.encode_type_hierarchy_items(items, uri),
              )
          }
        }
        Error(_) -> HandleResult(ws, json.null())
      }
  }
}

// --- Lifecycle ---

fn handle_initialize(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let ws2 = case params.root_uri(params) {
    Ok(root) -> workspace.set_root(ws, root)
    Error(_) -> ws
  }
  HandleResult(ws2, capabilities.initialize_result())
}

// --- Cross-file handlers ---

fn handle_definition(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  case get_document(ws, params) {
    Error(_) -> HandleResult(ws, json.null())
    Ok(#(uri, text)) ->
      case params.position(params) {
        Error(_) -> HandleResult(ws, json.null())
        Ok(#(line, character)) ->
          resolve_definition(ws, uri, text, line, character)
      }
  }
}

/// Three-layer definition resolution: same-file, blueprint ref, relation ref.
fn resolve_definition(
  ws: WorkspaceState,
  uri: String,
  text: String,
  line: Int,
  character: Int,
) -> HandleResult {
  // Layer 1: Same-file definition (extendables, type aliases).
  case definition.get_definition(text, line, character) {
    option.Some(#(l, c, len)) ->
      HandleResult(ws, responses.encode_definition(uri, l, c, len))
    option.None ->
      // Layer 2: Cross-file blueprint reference.
      case definition.get_blueprint_ref_at_position(text, line, character) {
        option.Some(bp_name) ->
          case workspace.find_cross_file_blueprint_def(ws, bp_name) {
            option.Some(#(u, l, c, len)) ->
              HandleResult(ws, responses.encode_definition(u, l, c, len))
            option.None -> HandleResult(ws, json.null())
          }
        option.None ->
          // Layer 3: Cross-file relation (dependency) reference.
          case
            definition.get_relation_ref_with_range_at_position(
              text,
              line,
              character,
            )
          {
            option.Some(#(ref_str, _)) ->
              case workspace.find_expectation_by_identifier(ws, ref_str) {
                option.Some(#(u, l, c, len)) ->
                  HandleResult(ws, responses.encode_definition(u, l, c, len))
                option.None -> HandleResult(ws, json.null())
              }
            option.None -> HandleResult(ws, json.null())
          }
      }
  }
}

fn handle_references(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case get_document(ws, params) {
    Error(_) -> empty
    Ok(#(uri, text)) ->
      case params.position(params) {
        Error(_) -> empty
        Ok(#(line, character)) -> {
          // Same-file references.
          let same_file =
            references.get_references(text, line, character)
            |> list.map(fn(r) {
              let #(l, c, len) = r
              responses.location(uri, responses.range(l, c, l, c + len))
            })
          // Cross-file: search other open documents for the blueprint name.
          let bp_name = references.get_blueprint_name_at(text, line, character)
          let cross_file = case bp_name {
            "" -> []
            _ -> collect_cross_file_references(ws, uri, bp_name)
          }
          HandleResult(
            ws,
            json.preprocessed_array(list.append(same_file, cross_file)),
          )
        }
      }
  }
}

/// Search all open documents (except current) for references to a name.
fn collect_cross_file_references(
  ws: WorkspaceState,
  current_uri: String,
  name: String,
) -> List(json.Json) {
  ws.documents
  |> dict.to_list
  |> list.filter(fn(entry) { entry.0 != current_uri })
  |> list.flat_map(fn(entry) {
    let #(u, text) = entry
    references.find_references_to_name(text, name)
    |> list.map(fn(r) {
      let #(l, c, len) = r
      responses.location(u, responses.range(l, c, l, c + len))
    })
  })
}

fn handle_workspace_symbol(ws: WorkspaceState, params: Dynamic) -> HandleResult {
  let query = case params.query(params) {
    Ok(q) -> string.lowercase(q)
    Error(_) -> ""
  }
  let #(ws2, symbols) = collect_workspace_symbols(ws, query)
  HandleResult(ws2, responses.encode_workspace_symbols(symbols))
}

/// Collect workspace symbols across all open documents, filtered by query.
fn collect_workspace_symbols(
  ws: WorkspaceState,
  query: String,
) -> #(WorkspaceState, List(#(String, workspace_symbols.WorkspaceSymbol))) {
  ws.documents
  |> dict.to_list
  |> collect_workspace_symbols_loop(ws, query, [])
}

fn collect_workspace_symbols_loop(
  entries: List(#(String, String)),
  ws: WorkspaceState,
  query: String,
  acc: List(#(String, workspace_symbols.WorkspaceSymbol)),
) -> #(WorkspaceState, List(#(String, workspace_symbols.WorkspaceSymbol))) {
  case entries {
    [] -> #(ws, list.reverse(acc))
    [#(uri, text), ..rest] -> {
      let #(ws2, symbols) =
        workspace.get_cached_workspace_symbols(ws, uri, text)
      let filtered = case query {
        "" -> symbols
        _ ->
          list.filter(symbols, fn(s) {
            string.contains(string.lowercase(s.name), query)
          })
      }
      let new_acc = list.fold(filtered, acc, fn(a, sym) { [#(uri, sym), ..a] })
      collect_workspace_symbols_loop(rest, ws2, query, new_acc)
    }
  }
}

fn handle_type_hierarchy_supertypes(
  ws: WorkspaceState,
  params: Dynamic,
) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case params.type_hierarchy_item_data(params) {
    Error(_) -> empty
    Ok(data) ->
      case data.kind {
        "expectation" if data.blueprint != "" ->
          find_blueprint_supertypes(ws, data.blueprint)
        _ -> empty
      }
  }
}

/// Find blueprint definitions that match the given blueprint name.
fn find_blueprint_supertypes(
  ws: WorkspaceState,
  blueprint_name: String,
) -> HandleResult {
  let items =
    ws.documents
    |> dict.to_list
    |> list.filter_map(fn(entry) {
      let #(uri, text) = entry
      // Only check blueprint files that might contain this name.
      case
        string.starts_with(text, "Blueprints")
        && string.contains(text, "\"" <> blueprint_name <> "\"")
      {
        False -> Error(Nil)
        True -> {
          let symbols = workspace_symbols.get_workspace_symbols(text)
          case
            list.find(symbols, fn(s) { s.name == blueprint_name && s.kind == 5 })
          {
            Ok(sym) ->
              Ok(responses.encode_type_hierarchy_item(
                type_hierarchy.TypeHierarchyItem(
                  name: sym.name,
                  kind: type_hierarchy.BlueprintKind,
                  line: sym.line,
                  col: sym.col,
                  name_len: sym.name_len,
                  blueprint: "",
                ),
                uri,
              ))
            Error(_) -> Error(Nil)
          }
        }
      }
    })
  HandleResult(ws, json.preprocessed_array(items))
}

fn handle_type_hierarchy_subtypes(
  ws: WorkspaceState,
  params: Dynamic,
) -> HandleResult {
  let empty = HandleResult(ws, json.preprocessed_array([]))
  case params.type_hierarchy_item_data(params) {
    Error(_) -> empty
    Ok(data) ->
      case data.kind {
        "blueprint" -> find_expectation_subtypes(ws, data.name)
        _ -> empty
      }
  }
}

/// Find expectations that reference the given blueprint name.
fn find_expectation_subtypes(
  ws: WorkspaceState,
  blueprint_name: String,
) -> HandleResult {
  let items =
    ws.documents
    |> dict.to_list
    |> list.flat_map(fn(entry) {
      let #(uri, text) = entry
      case
        string.starts_with(text, "Expectations")
        && string.contains(text, "\"" <> blueprint_name <> "\"")
      {
        False -> []
        True -> collect_subtypes_from_file(text, blueprint_name, uri)
      }
    })
  HandleResult(ws, json.preprocessed_array(items))
}

/// Scan a file for expectation items that reference the target blueprint.
fn collect_subtypes_from_file(
  text: String,
  blueprint_name: String,
  uri: String,
) -> List(json.Json) {
  string.split(text, "\n")
  |> list.index_map(fn(line_text, idx) { #(idx, line_text) })
  |> list.filter_map(fn(entry) {
    let #(line_idx, line_text) = entry
    let trimmed = string.trim_start(line_text)
    case string.starts_with(trimmed, "* \"") {
      False -> Error(Nil)
      True -> {
        // Extract item name position.
        case string.split(trimmed, "\"") {
          [_, item_name, ..] -> {
            let col = case string.split(line_text, "\"") {
              [before, ..] -> string.length(before)
              _ -> 0
            }
            let items =
              type_hierarchy.prepare_type_hierarchy(text, line_idx, col + 1)
            case list.find(items, fn(i) { i.blueprint == blueprint_name }) {
              Ok(item) ->
                Ok(responses.encode_type_hierarchy_item(
                  type_hierarchy.TypeHierarchyItem(
                    ..item,
                    kind: type_hierarchy.ExpectationKind,
                  ),
                  uri,
                ))
              Error(_) -> {
                let _ = item_name
                Error(Nil)
              }
            }
          }
          _ -> Error(Nil)
        }
      }
    }
  })
}

// --- Helpers ---

/// Look up document text for the URI in params.
fn get_document(
  ws: WorkspaceState,
  dyn: Dynamic,
) -> Result(#(String, String), Nil) {
  case params.uri(dyn) {
    Ok(uri) ->
      case workspace.get_document(ws, uri) {
        option.Some(text) -> Ok(#(uri, text))
        option.None -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

/// Extract text from content at a given line, column, and length.
fn extract_text_at(content: String, line: Int, col: Int, length: Int) -> String {
  let lines = string.split(content, "\n")
  case list.drop(lines, line) {
    [target_line, ..] -> string.slice(target_line, col, length)
    [] -> ""
  }
}

/// Convert a diagnostic code string to a DiagnosticCode value.
fn string_to_diagnostic_code(code: String) -> DiagnosticCode {
  case code {
    "quoted-field-name" -> QuotedFieldName
    "blueprint-not-found" -> BlueprintNotFound
    "dependency-not-found" -> DependencyNotFound
    "missing-required-fields" -> MissingRequiredFields
    "type-mismatch" -> TypeMismatch
    "unknown-field" -> UnknownField
    "unused-extendable" -> UnusedExtendable
    "unused-type-alias" -> UnusedTypeAlias
    "dead-blueprint" -> DeadBlueprint
    _ -> NoDiagnosticCode
  }
}
