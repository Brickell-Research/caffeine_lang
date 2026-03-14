import caffeine_lang/frontend/ast.{
  type ExpectItem, type ExpectsFile, type Extendable, type MeasurementItem,
  type MeasurementsFile, type Parsed, type TypeAlias,
}
import caffeine_lsp/file_utils
import caffeine_lsp/lsp_types.{SkClass, SkTypeParameter, SkVariable}
import caffeine_lsp/position_utils
import gleam/list
import gleam/result
import gleam/string

/// A flat workspace symbol for cross-file search.
pub type WorkspaceSymbol {
  WorkspaceSymbol(name: String, kind: Int, line: Int, col: Int, name_len: Int)
}

/// Return flat top-level symbols from source text for workspace symbol search.
/// Includes type aliases, extendables, measurement items, and expect items.
/// Excludes fields and block wrappers.
pub fn get_workspace_symbols(content: String) -> List(WorkspaceSymbol) {
  let lines = string.split(content, "\n")
  case file_utils.parse(content) {
    Ok(file_utils.Measurements(file)) -> measurements_symbols(file, lines)
    Ok(file_utils.Expects(file)) -> expects_symbols(file, lines)
    Error(_) -> []
  }
}

fn measurements_symbols(
  file: MeasurementsFile(Parsed),
  lines: List(String),
) -> List(WorkspaceSymbol) {
  let alias_syms =
    list.map(file.type_aliases, fn(ta) { type_alias_symbol(ta, lines) })
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, lines) })
  let item_syms =
    list.map(file.items, fn(item) { measurement_item_symbol(item, lines) })
  list.flatten([alias_syms, ext_syms, item_syms])
}

fn expects_symbols(
  file: ExpectsFile(Parsed),
  lines: List(String),
) -> List(WorkspaceSymbol) {
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, lines) })
  let item_syms =
    list.flat_map(file.blocks, fn(b) {
      list.map(b.items, fn(item) { expect_item_symbol(item, lines) })
    })
  list.flatten([ext_syms, item_syms])
}

fn type_alias_symbol(ta: TypeAlias, lines: List(String)) -> WorkspaceSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, ta.name)
    |> result.unwrap(#(0, 0))
  WorkspaceSymbol(
    ta.name,
    lsp_types.symbol_kind_to_int(SkTypeParameter),
    line,
    col,
    string.length(ta.name),
  )
}

fn extendable_symbol(ext: Extendable, lines: List(String)) -> WorkspaceSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, ext.name)
    |> result.unwrap(#(0, 0))
  WorkspaceSymbol(
    ext.name,
    lsp_types.symbol_kind_to_int(SkVariable),
    line,
    col,
    string.length(ext.name),
  )
}

fn measurement_item_symbol(
  item: MeasurementItem,
  lines: List(String),
) -> WorkspaceSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, item.name)
    |> result.unwrap(#(0, 0))
  WorkspaceSymbol(
    item.name,
    lsp_types.symbol_kind_to_int(SkClass),
    line,
    col,
    string.length(item.name),
  )
}

fn expect_item_symbol(item: ExpectItem, lines: List(String)) -> WorkspaceSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, item.name)
    |> result.unwrap(#(0, 0))
  WorkspaceSymbol(
    item.name,
    lsp_types.symbol_kind_to_int(SkClass),
    line,
    col,
    string.length(item.name),
  )
}
