/// Workspace state management — file tracking, blueprint/expectation indices,
/// and validated blueprint caching. Pure data types and update functions.
import caffeine_lang/linker/blueprints.{type Blueprint, type BlueprintValidated}
import caffeine_lsp/linker_diagnostics
import caffeine_lsp/server/workspace_parsers
import caffeine_lsp/workspace_symbols
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/set.{type Set}
import gleam/string

/// Immutable workspace state snapshot.
pub type WorkspaceState {
  WorkspaceState(
    root: Option(String),
    files: Set(String),
    documents: Dict(String, String),
    blueprint_index: Dict(String, Set(String)),
    referenced_blueprint_index: Dict(String, Set(String)),
    expectation_index: Dict(String, Dict(String, String)),
    validated_blueprints_cache: Dict(
      String,
      List(Blueprint(BlueprintValidated)),
    ),
    merged_validated_blueprints: Option(List(Blueprint(BlueprintValidated))),
    validated_blueprints_dirty: Bool,
    workspace_symbols_cache: Dict(
      String,
      List(workspace_symbols.WorkspaceSymbol),
    ),
  )
}

/// Create a new empty workspace state.
pub fn new() -> WorkspaceState {
  WorkspaceState(
    root: option.None,
    files: set.new(),
    documents: dict.new(),
    blueprint_index: dict.new(),
    referenced_blueprint_index: dict.new(),
    expectation_index: dict.new(),
    validated_blueprints_cache: dict.new(),
    merged_validated_blueprints: option.None,
    validated_blueprints_dirty: True,
    workspace_symbols_cache: dict.new(),
  )
}

/// Set the workspace root path.
pub fn set_root(state: WorkspaceState, root: String) -> WorkspaceState {
  let clean_root = case string.starts_with(root, "file://") {
    True -> string.drop_start(root, 7)
    False -> root
  }
  WorkspaceState(..state, root: option.Some(clean_root))
}

/// Register a file URI in the workspace.
pub fn add_file(state: WorkspaceState, uri: String) -> WorkspaceState {
  WorkspaceState(..state, files: set.insert(state.files, uri))
}

/// Store an open document's text.
pub fn document_opened(
  state: WorkspaceState,
  uri: String,
  text: String,
) -> WorkspaceState {
  WorkspaceState(..state, documents: dict.insert(state.documents, uri, text))
}

/// Update a document's text.
pub fn document_changed(
  state: WorkspaceState,
  uri: String,
  text: String,
) -> WorkspaceState {
  WorkspaceState(..state, documents: dict.insert(state.documents, uri, text))
}

/// Remove a document from the open documents map.
pub fn document_closed(state: WorkspaceState, uri: String) -> WorkspaceState {
  WorkspaceState(..state, documents: dict.delete(state.documents, uri))
}

/// Get document text: prefer open document, return None if not found.
pub fn get_document(state: WorkspaceState, uri: String) -> Option(String) {
  case dict.get(state.documents, uri) {
    Ok(text) -> option.Some(text)
    Error(_) -> option.None
  }
}

/// Get all document URIs in the workspace.
pub fn all_file_uris(state: WorkspaceState) -> List(String) {
  set.to_list(state.files)
}

/// Collect all known blueprint names across the workspace.
pub fn all_known_blueprints(state: WorkspaceState) -> List(String) {
  state.blueprint_index
  |> dict.values
  |> list.flat_map(set.to_list)
}

/// Collect all referenced blueprint names across the workspace.
pub fn all_referenced_blueprints(state: WorkspaceState) -> List(String) {
  state.referenced_blueprint_index
  |> dict.values
  |> list.flat_map(set.to_list)
}

/// Collect all known expectation dotted identifiers.
pub fn all_known_expectation_identifiers(state: WorkspaceState) -> List(String) {
  state.expectation_index
  |> dict.values
  |> list.flat_map(dict.values)
}

/// Update indices for a file. Returns the updated state and whether indices changed.
pub fn update_indices_for_file(
  state: WorkspaceState,
  uri: String,
  text: String,
) -> #(WorkspaceState, Bool) {
  let #(bp_index, exp_index, changed) =
    workspace_parsers.apply_index_updates(
      uri,
      text,
      state.blueprint_index,
      state.expectation_index,
    )

  // Update referenced blueprint index.
  let new_refs =
    workspace_parsers.extract_referenced_blueprint_names(text)
    |> set.from_list
  let ref_index = case set.is_empty(new_refs) {
    True -> dict.delete(state.referenced_blueprint_index, uri)
    False -> dict.insert(state.referenced_blueprint_index, uri, new_refs)
  }

  // Update validated blueprints cache.
  let #(vb_cache, vb_dirty) = case dict.has_key(bp_index, uri) {
    True -> try_compile_blueprints(state.validated_blueprints_cache, uri, text)
    False -> {
      case dict.has_key(state.validated_blueprints_cache, uri) {
        True -> #(dict.delete(state.validated_blueprints_cache, uri), True)
        False -> #(state.validated_blueprints_cache, False)
      }
    }
  }

  let new_state =
    WorkspaceState(
      ..state,
      blueprint_index: bp_index,
      expectation_index: exp_index,
      referenced_blueprint_index: ref_index,
      validated_blueprints_cache: vb_cache,
      validated_blueprints_dirty: state.validated_blueprints_dirty || vb_dirty,
      workspace_symbols_cache: dict.delete(state.workspace_symbols_cache, uri),
    )

  #(new_state, changed)
}

/// Remove a file from all indices.
pub fn remove_file(
  state: WorkspaceState,
  uri: String,
) -> #(WorkspaceState, Bool) {
  let had_bp = dict.has_key(state.blueprint_index, uri)
  let had_refs = dict.has_key(state.referenced_blueprint_index, uri)
  let had_exp = dict.has_key(state.expectation_index, uri)
  let had_vb = dict.has_key(state.validated_blueprints_cache, uri)

  let new_state =
    WorkspaceState(
      ..state,
      files: set.delete(state.files, uri),
      blueprint_index: dict.delete(state.blueprint_index, uri),
      referenced_blueprint_index: dict.delete(
        state.referenced_blueprint_index,
        uri,
      ),
      expectation_index: dict.delete(state.expectation_index, uri),
      validated_blueprints_cache: dict.delete(
        state.validated_blueprints_cache,
        uri,
      ),
      validated_blueprints_dirty: state.validated_blueprints_dirty || had_vb,
      workspace_symbols_cache: dict.delete(state.workspace_symbols_cache, uri),
    )

  #(new_state, had_bp || had_refs || had_exp)
}

/// Get all validated blueprints, merging from cache. Lazy — only recomputes
/// when dirty.
pub fn all_validated_blueprints(
  state: WorkspaceState,
) -> #(WorkspaceState, List(Blueprint(BlueprintValidated))) {
  case state.validated_blueprints_dirty, state.merged_validated_blueprints {
    False, option.Some(merged) -> #(state, merged)
    _, _ -> {
      let merged =
        state.validated_blueprints_cache
        |> dict.values
        |> list.flatten
      let new_state =
        WorkspaceState(
          ..state,
          merged_validated_blueprints: option.Some(merged),
          validated_blueprints_dirty: False,
        )
      #(new_state, merged)
    }
  }
}

/// Look up a cross-file blueprint definition by item name.
/// Returns `#(uri, line, col, name_len)` or None.
pub fn find_cross_file_blueprint_def(
  state: WorkspaceState,
  item_name: String,
) -> Option(#(String, Int, Int, Int)) {
  state.blueprint_index
  |> dict.to_list
  |> find_blueprint_def_loop(item_name, state)
}

fn find_blueprint_def_loop(
  entries: List(#(String, Set(String))),
  item_name: String,
  state: WorkspaceState,
) -> Option(#(String, Int, Int, Int)) {
  case entries {
    [] -> option.None
    [#(uri, names), ..rest] -> {
      case set.contains(names, item_name) {
        False -> find_blueprint_def_loop(rest, item_name, state)
        True -> {
          case get_document(state, uri) {
            option.None -> find_blueprint_def_loop(rest, item_name, state)
            option.Some(text) -> {
              case
                workspace_parsers.find_blueprint_item_location(text, item_name)
              {
                Ok(#(line, col, name_len)) ->
                  option.Some(#(uri, line, col, name_len))
                Error(_) -> find_blueprint_def_loop(rest, item_name, state)
              }
            }
          }
        }
      }
    }
  }
}

/// Look up an expectation definition by dotted identifier.
pub fn find_expectation_by_identifier(
  state: WorkspaceState,
  dotted_id: String,
) -> Option(#(String, Int, Int, Int)) {
  let parts = string.split(dotted_id, ".")
  case list.length(parts) == 4 {
    False -> option.None
    True -> {
      let assert Ok(item_name) = list.last(parts)
      state.expectation_index
      |> dict.to_list
      |> find_expectation_loop(item_name, dotted_id, state)
    }
  }
}

fn find_expectation_loop(
  entries: List(#(String, Dict(String, String))),
  item_name: String,
  dotted_id: String,
  state: WorkspaceState,
) -> Option(#(String, Int, Int, Int)) {
  case entries {
    [] -> option.None
    [#(uri, id_map), ..rest] -> {
      case dict.get(id_map, item_name) {
        Ok(id) if id == dotted_id -> {
          case get_document(state, uri) {
            option.None ->
              find_expectation_loop(rest, item_name, dotted_id, state)
            option.Some(text) -> {
              case
                workspace_parsers.find_blueprint_item_location(text, item_name)
              {
                Ok(#(line, col, name_len)) ->
                  option.Some(#(uri, line, col, name_len))
                Error(_) ->
                  find_expectation_loop(rest, item_name, dotted_id, state)
              }
            }
          }
        }
        _ -> find_expectation_loop(rest, item_name, dotted_id, state)
      }
    }
  }
}

/// Get cached workspace symbols for a file, computing on first access.
pub fn get_cached_workspace_symbols(
  state: WorkspaceState,
  uri: String,
  text: String,
) -> #(WorkspaceState, List(workspace_symbols.WorkspaceSymbol)) {
  case dict.get(state.workspace_symbols_cache, uri) {
    Ok(cached) -> #(state, cached)
    Error(_) -> {
      let symbols = workspace_symbols.get_workspace_symbols(text)
      let new_state =
        WorkspaceState(
          ..state,
          workspace_symbols_cache: dict.insert(
            state.workspace_symbols_cache,
            uri,
            symbols,
          ),
        )
      #(new_state, symbols)
    }
  }
}

/// Try to compile and validate blueprints from file content, updating the cache.
fn try_compile_blueprints(
  cache: Dict(String, List(Blueprint(BlueprintValidated))),
  uri: String,
  text: String,
) -> #(Dict(String, List(Blueprint(BlueprintValidated))), Bool) {
  case linker_diagnostics.compile_validated_blueprints(text) {
    Ok(blueprints) -> #(dict.insert(cache, uri, blueprints), True)
    Error(_) -> #(dict.delete(cache, uri), True)
  }
}

/// Directories to skip during workspace scanning.
pub const skip_dirs = [
  "node_modules", ".git", "build", ".claude", "dist", "vendor", ".deno",
]
