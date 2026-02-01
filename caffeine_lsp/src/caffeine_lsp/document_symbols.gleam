import caffeine_lang/common/accepted_types
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type TypeAlias,
}
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/json
import gleam/list
import gleam/string

// LSP SymbolKind constants
const symbol_kind_module = 2

const symbol_kind_class = 5

const symbol_kind_property = 7

const symbol_kind_variable = 13

const symbol_kind_type_parameter = 26

/// Analyze source text and return DocumentSymbol JSON objects for the outline.
pub fn get_symbols(content: String) -> List(json.Json) {
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> blueprints_file_symbols(file, content)
    Ok(file_utils.Expects(file)) -> expects_file_symbols(file, content)
    Error(_) -> []
  }
}

fn blueprints_file_symbols(
  file: BlueprintsFile,
  content: String,
) -> List(json.Json) {
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

fn expects_file_symbols(file: ExpectsFile, content: String) -> List(json.Json) {
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

fn type_alias_symbol(ta: TypeAlias, content: String) -> json.Json {
  let #(line, col) = position_utils.find_name_position(content, ta.name)
  let detail = accepted_types.accepted_type_to_string(ta.type_)
  symbol_json(
    ta.name,
    detail,
    symbol_kind_type_parameter,
    line,
    col,
    string.length(ta.name),
    [],
  )
}

fn extendable_symbol(ext: Extendable, content: String) -> json.Json {
  let #(line, col) = position_utils.find_name_position(content, ext.name)
  let detail = case ext.kind {
    ast.ExtendableRequires -> "Requires"
    ast.ExtendableProvides -> "Provides"
  }
  symbol_json(
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
  children: List(json.Json),
) -> json.Json {
  // For blocks, search for a keyword that starts the block
  let search = case string.starts_with(name, "Blueprints") {
    True -> "Blueprints"
    False -> "Expectations"
  }
  let #(line, col) = position_utils.find_name_position(content, search)
  symbol_json(
    name,
    "",
    symbol_kind_module,
    line,
    col,
    string.length(name),
    children,
  )
}

fn blueprint_item_symbol(item: BlueprintItem, content: String) -> json.Json {
  let #(line, col) = position_utils.find_name_position(content, item.name)
  let req_fields =
    list.map(item.requires.fields, fn(f) { field_symbol(f, content) })
  let prov_fields =
    list.map(item.provides.fields, fn(f) { field_symbol(f, content) })
  let children = list.flatten([req_fields, prov_fields])
  symbol_json(
    item.name,
    "",
    symbol_kind_class,
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn expect_item_symbol(item: ExpectItem, content: String) -> json.Json {
  let #(line, col) = position_utils.find_name_position(content, item.name)
  let children =
    list.map(item.provides.fields, fn(f) { field_symbol(f, content) })
  symbol_json(
    item.name,
    "",
    symbol_kind_class,
    line,
    col,
    string.length(item.name),
    children,
  )
}

fn field_symbol(field: Field, content: String) -> json.Json {
  let #(line, col) = position_utils.find_name_position(content, field.name)
  let detail = case field.value {
    ast.TypeValue(t) -> accepted_types.accepted_type_to_string(t)
    ast.LiteralValue(lit) -> literal_to_string(lit)
  }
  symbol_json(
    field.name,
    detail,
    symbol_kind_property,
    line,
    col,
    string.length(field.name),
    [],
  )
}

fn literal_to_string(lit: ast.Literal) -> String {
  case lit {
    ast.LiteralString(s) -> "\"" <> s <> "\""
    ast.LiteralInteger(n) -> string.inspect(n)
    ast.LiteralFloat(f) -> string.inspect(f)
    ast.LiteralTrue -> "true"
    ast.LiteralFalse -> "false"
    ast.LiteralList(_) -> "[...]"
    ast.LiteralStruct(_) -> "{...}"
  }
}

// --- JSON builder ---

fn symbol_json(
  name: String,
  detail: String,
  kind: Int,
  line: Int,
  col: Int,
  name_len: Int,
  children: List(json.Json),
) -> json.Json {
  let range =
    json.object([
      #(
        "start",
        json.object([
          #("line", json.int(line)),
          #("character", json.int(col)),
        ]),
      ),
      #(
        "end",
        json.object([
          #("line", json.int(line)),
          #("character", json.int(col + name_len)),
        ]),
      ),
    ])
  json.object([
    #("name", json.string(name)),
    #("detail", json.string(detail)),
    #("kind", json.int(kind)),
    #("range", range),
    #("selectionRange", range),
    #("children", json.preprocessed_array(children)),
  ])
}
