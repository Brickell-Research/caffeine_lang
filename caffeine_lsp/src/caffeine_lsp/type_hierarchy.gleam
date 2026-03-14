import caffeine_lang/frontend/ast.{
  type ExpectItem, type ExpectsFile, type MeasurementItem, type MeasurementsFile,
  type Parsed,
}
import caffeine_lsp/file_utils
import caffeine_lsp/position_utils
import gleam/list
import gleam/option
import gleam/result
import gleam/string

/// Whether the item is a measurement (supertype) or expectation (subtype).
pub type TypeHierarchyKind {
  /// A measurement item acts as a supertype.
  MeasurementKind
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
    /// For expectations: the measurement name they reference.
    /// For measurements: empty string.
    measurement: String,
  )
}

/// Prepare type hierarchy at cursor position. Returns items if cursor is on
/// a measurement item name or expect item name.
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
    Ok(file_utils.Measurements(file)) -> find_in_measurements(file, lines, name)
    Ok(file_utils.Expects(file)) -> find_in_expects(file, lines, name)
    Error(_) -> []
  }
}

/// Search measurement items for a matching name.
fn find_in_measurements(
  file: MeasurementsFile(Parsed),
  lines: List(String),
  name: String,
) -> List(TypeHierarchyItem) {
  file.items
  |> list.filter_map(fn(item) { match_measurement_item(item, lines, name) })
}

/// Return a hierarchy item if this measurement item matches the name.
fn match_measurement_item(
  item: MeasurementItem,
  lines: List(String),
  name: String,
) -> Result(TypeHierarchyItem, Nil) {
  case item.name == name {
    False -> Error(Nil)
    True -> {
      let #(line, col) =
        position_utils.find_name_position_in_lines(lines, item.name)
        |> result.unwrap(#(0, 0))
      Ok(TypeHierarchyItem(
        name: item.name,
        kind: MeasurementKind,
        line: line,
        col: col,
        name_len: string.length(item.name),
        measurement: "",
      ))
    }
  }
}

/// Search expect items for a matching name.
fn find_in_expects(
  file: ExpectsFile(Parsed),
  lines: List(String),
  name: String,
) -> List(TypeHierarchyItem) {
  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.filter_map(fn(item) {
      match_expect_item(item, lines, name, block.measurement)
    })
  })
}

/// Return a hierarchy item if this expect item matches the name.
fn match_expect_item(
  item: ExpectItem,
  lines: List(String),
  name: String,
  measurement: option.Option(String),
) -> Result(TypeHierarchyItem, Nil) {
  case item.name == name {
    False -> Error(Nil)
    True -> {
      let #(line, col) =
        position_utils.find_name_position_in_lines(lines, item.name)
        |> result.unwrap(#(0, 0))
      Ok(TypeHierarchyItem(
        name: item.name,
        kind: ExpectationKind,
        line: line,
        col: col,
        name_len: string.length(item.name),
        measurement: option.unwrap(measurement, ""),
      ))
    }
  }
}
