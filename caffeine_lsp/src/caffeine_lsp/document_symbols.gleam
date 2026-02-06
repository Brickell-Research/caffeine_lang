import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type TypeAlias,
}
import caffeine_lang/types
import caffeine_lsp/file_utils
import caffeine_lsp/lsp_types.{
  SkClass, SkModule, SkProperty, SkTypeParameter, SkVariable,
}
import caffeine_lsp/position_utils
import gleam/list
import gleam/string

/// A document symbol for the editor outline.
pub type DocumentSymbol {
  DocumentSymbol(
    name: String,
    detail: String,
    kind: Int,
    line: Int,
    col: Int,
    name_len: Int,
    children: List(DocumentSymbol),
  )
}

/// Analyze source text and return document symbols for the outline.
pub fn get_symbols(content: String) -> List(DocumentSymbol) {
  let lines = string.split(content, "\n")
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> blueprints_file_symbols(file, lines)
    Ok(file_utils.Expects(file)) -> expects_file_symbols(file, lines)
    Error(_) -> []
  }
}

fn blueprints_file_symbols(
  file: BlueprintsFile,
  lines: List(String),
) -> List(DocumentSymbol) {
  let alias_syms =
    list.map(file.type_aliases, fn(ta) { type_alias_symbol(ta, lines) })
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, lines) })
  let block_syms =
    list.map(file.blocks, fn(b) {
      let name = "Blueprints for " <> string.join(b.artifacts, ", ")
      let children =
        list.map(b.items, fn(item) { blueprint_item_symbol(item, lines) })
      block_symbol(name, lines, children)
    })
  list.flatten([alias_syms, ext_syms, block_syms])
}

fn expects_file_symbols(
  file: ExpectsFile,
  lines: List(String),
) -> List(DocumentSymbol) {
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, lines) })
  let block_syms =
    list.map(file.blocks, fn(b) {
      let name = "Expectations for " <> b.blueprint
      let children =
        list.map(b.items, fn(item) { expect_item_symbol(item, lines) })
      block_symbol(name, lines, children)
    })
  list.flatten([ext_syms, block_syms])
}

fn type_alias_symbol(ta: TypeAlias, lines: List(String)) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position_in_lines(lines, ta.name)
  let detail = types.parsed_type_to_string(ta.type_)
  DocumentSymbol(
    ta.name,
    detail,
    lsp_types.symbol_kind_to_int(SkTypeParameter),
    line,
    col,
    string.length(ta.name),
    [],
  )
}

fn extendable_symbol(ext: Extendable, lines: List(String)) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position_in_lines(lines, ext.name)
  let detail = ast.extendable_kind_to_string(ext.kind)
  DocumentSymbol(
    ext.name,
    detail,
    lsp_types.symbol_kind_to_int(SkVariable),
    line,
    col,
    string.length(ext.name),
    [],
  )
}

fn block_symbol(
  name: String,
  lines: List(String),
  children: List(DocumentSymbol),
) -> DocumentSymbol {
  // For blocks, search for a keyword that starts the block
  let search = case string.starts_with(name, "Blueprints") {
    True -> "Blueprints"
    False -> "Expectations"
  }
  let #(line, col) = position_utils.find_name_position_in_lines(lines, search)
  DocumentSymbol(
    name,
    "",
    lsp_types.symbol_kind_to_int(SkModule),
    line,
    col,
    string.length(name),
    children,
  )
}

fn blueprint_item_symbol(
  item: BlueprintItem,
  lines: List(String),
) -> DocumentSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, item.name)
  let req_fields =
    list.map(item.requires.fields, fn(f) { field_symbol(f, lines) })
  let prov_fields =
    list.map(item.provides.fields, fn(f) { field_symbol(f, lines) })
  let children = list.flatten([req_fields, prov_fields])
  DocumentSymbol(
    item.name,
    "",
    lsp_types.symbol_kind_to_int(SkClass),
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn expect_item_symbol(item: ExpectItem, lines: List(String)) -> DocumentSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, item.name)
  let children =
    list.map(item.provides.fields, fn(f) { field_symbol(f, lines) })
  DocumentSymbol(
    item.name,
    "",
    lsp_types.symbol_kind_to_int(SkClass),
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn field_symbol(field: Field, lines: List(String)) -> DocumentSymbol {
  let #(line, col) =
    position_utils.find_name_position_in_lines(lines, field.name)
  let detail = ast.value_to_string(field.value)
  DocumentSymbol(
    field.name,
    detail,
    lsp_types.symbol_kind_to_int(SkProperty),
    line,
    col,
    string.length(field.name),
    [],
  )
}
