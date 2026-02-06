import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
}
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/list
import gleam/string

/// Whether the item is a blueprint (supertype) or expectation (subtype).
pub type TypeHierarchyKind {
  /// A blueprint item acts as a supertype.
  BlueprintKind
  /// An expectation item acts as a subtype.
  ExpectationKind
}

/// A type hierarchy item for the LSP protocol.
pub type TypeHierarchyItem {
  TypeHierarchyItem(
    name: String,
    kind: TypeHierarchyKind,
    line: Int,
    col: Int,
    name_len: Int,
    /// For expectations: the blueprint name they reference.
    /// For blueprints: empty string.
    blueprint: String,
  )
}

/// Prepare type hierarchy at cursor position. Returns items if cursor is on
/// a blueprint item name or expect item name.
pub fn prepare_type_hierarchy(
  content: String,
  line: Int,
  character: Int,
) -> List(TypeHierarchyItem) {
  let word = position_utils.extract_word_at(content, line, character)
  case word {
    "" -> []
    name -> find_hierarchy_item(content, name)
  }
}

/// Look up hierarchy item by name in the parsed file.
fn find_hierarchy_item(content: String, name: String) -> List(TypeHierarchyItem) {
  let lines = string.split(content, "\n")
  case file_utils.parse(content) {
    Ok(file_utils.Blueprints(file)) -> find_in_blueprints(file, lines, name)
    Ok(file_utils.Expects(file)) -> find_in_expects(file, lines, name)
    Error(_) -> []
  }
}

/// Search blueprint items for a matching name.
fn find_in_blueprints(
  file: BlueprintsFile,
  lines: List(String),
  name: String,
) -> List(TypeHierarchyItem) {
  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.filter_map(fn(item) { match_blueprint_item(item, lines, name) })
  })
}

/// Return a hierarchy item if this blueprint item matches the name.
fn match_blueprint_item(
  item: BlueprintItem,
  lines: List(String),
  name: String,
) -> Result(TypeHierarchyItem, Nil) {
  case item.name == name {
    False -> Error(Nil)
    True -> {
      let #(line, col) =
        position_utils.find_name_position_in_lines(lines, item.name)
      Ok(TypeHierarchyItem(
        name: item.name,
        kind: BlueprintKind,
        line: line,
        col: col,
        name_len: string.length(item.name),
        blueprint: "",
      ))
    }
  }
}

/// Search expect items for a matching name.
fn find_in_expects(
  file: ExpectsFile,
  lines: List(String),
  name: String,
) -> List(TypeHierarchyItem) {
  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.filter_map(fn(item) {
      match_expect_item(item, lines, name, block.blueprint)
    })
  })
}

/// Return a hierarchy item if this expect item matches the name.
fn match_expect_item(
  item: ExpectItem,
  lines: List(String),
  name: String,
  blueprint: String,
) -> Result(TypeHierarchyItem, Nil) {
  case item.name == name {
    False -> Error(Nil)
    True -> {
      let #(line, col) =
        position_utils.find_name_position_in_lines(lines, item.name)
      Ok(TypeHierarchyItem(
        name: item.name,
        kind: ExpectationKind,
        line: line,
        col: col,
        name_len: string.length(item.name),
        blueprint: blueprint,
      ))
    }
  }
}
