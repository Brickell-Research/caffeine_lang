/// LSP request router and single-document feature handlers.
import caffeine_lang/frontend/formatter
import caffeine_lsp/code_actions.{ActionDiagnostic}
import caffeine_lsp/completion
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
import caffeine_lsp/rename
import caffeine_lsp/selection_range
import caffeine_lsp/semantic_tokens
import caffeine_lsp/server/params
import caffeine_lsp/server/responses
import caffeine_lsp/server/workspace.{type WorkspaceState}
import caffeine_lsp/signature_help
import caffeine_lsp/type_hierarchy
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
    "textDocument/typeHierarchy/prepare" ->
      Ok(handle_type_hierarchy_prepare(ws, params))
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
