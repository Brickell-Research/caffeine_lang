import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type TypeAlias,
}
import caffeine_lang/types
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/list
import gleam/string

// LSP SymbolKind constants
const symbol_kind_module = 2

const symbol_kind_class = 5

const symbol_kind_property = 7

const symbol_kind_variable = 13

const symbol_kind_type_parameter = 26

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
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> blueprints_file_symbols(file, content)
    Ok(file_utils.Expects(file)) -> expects_file_symbols(file, content)
    Error(_) -> []
  }
}

fn blueprints_file_symbols(
  file: BlueprintsFile,
  content: String,
) -> List(DocumentSymbol) {
  let alias_syms =
    list.map(file.type_aliases, fn(ta) { type_alias_symbol(ta, content) })
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, content) })
  let block_syms =
    list.map(file.blocks, fn(b) {
      let name = "Blueprints for " <> string.join(b.artifacts, ", ")
      let children =
        list.map(b.items, fn(item) { blueprint_item_symbol(item, content) })
      block_symbol(name, content, children)
    })
  list.flatten([alias_syms, ext_syms, block_syms])
}

fn expects_file_symbols(
  file: ExpectsFile,
  content: String,
) -> List(DocumentSymbol) {
  let ext_syms =
    list.map(file.extendables, fn(e) { extendable_symbol(e, content) })
  let block_syms =
    list.map(file.blocks, fn(b) {
      let name = "Expectations for " <> b.blueprint
      let children =
        list.map(b.items, fn(item) { expect_item_symbol(item, content) })
      block_symbol(name, content, children)
    })
  list.flatten([ext_syms, block_syms])
}

fn type_alias_symbol(ta: TypeAlias, content: String) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position(content, ta.name)
  let detail = types.parsed_type_to_string(ta.type_)
  DocumentSymbol(
    ta.name,
    detail,
    symbol_kind_type_parameter,
    line,
    col,
    string.length(ta.name),
    [],
  )
}

fn extendable_symbol(ext: Extendable, content: String) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position(content, ext.name)
  let detail = ast.extendable_kind_to_string(ext.kind)
  DocumentSymbol(
    ext.name,
    detail,
    symbol_kind_variable,
    line,
    col,
    string.length(ext.name),
    [],
  )
}

fn block_symbol(
  name: String,
  content: String,
  children: List(DocumentSymbol),
) -> DocumentSymbol {
  // For blocks, search for a keyword that starts the block
  let search = case string.starts_with(name, "Blueprints") {
    True -> "Blueprints"
    False -> "Expectations"
  }
  let #(line, col) = position_utils.find_name_position(content, search)
  DocumentSymbol(
    name,
    "",
    symbol_kind_module,
    line,
    col,
    string.length(name),
    children,
  )
}

fn blueprint_item_symbol(item: BlueprintItem, content: String) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position(content, item.name)
  let req_fields =
    list.map(item.requires.fields, fn(f) { field_symbol(f, content) })
  let prov_fields =
    list.map(item.provides.fields, fn(f) { field_symbol(f, content) })
  let children = list.flatten([req_fields, prov_fields])
  DocumentSymbol(
    item.name,
    "",
    symbol_kind_class,
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn expect_item_symbol(item: ExpectItem, content: String) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position(content, item.name)
  let children =
    list.map(item.provides.fields, fn(f) { field_symbol(f, content) })
  DocumentSymbol(
    item.name,
    "",
    symbol_kind_class,
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn field_symbol(field: Field, content: String) -> DocumentSymbol {
  let #(line, col) = position_utils.find_name_position(content, field.name)
  let detail = case field.value {
    ast.TypeValue(t) -> types.parsed_type_to_string(t)
    ast.LiteralValue(lit) -> ast.literal_to_string(lit)
  }
  DocumentSymbol(
    field.name,
    detail,
    symbol_kind_property,
    line,
    col,
    string.length(field.name),
    [],
  )
}
