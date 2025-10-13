import caffeine_lang/types/common/accepted_types
import caffeine_lang/phase_1/parser/utils/glaml_helpers as gh
import caffeine_lang/types/ast/basic_type
import glaml
import gleam/dict
import gleam/result
import gleam/string

// ==== Public ====
/// Given a specification file, returns a list of basic types.
pub fn parse_basic_types_specification(
  file_path: String,
) -> Result(List(basic_type.BasicType), String) {
  gh.parse_specification(file_path, dict.new(), parse_basic_type, "basic_types")
}

// ==== Private ====
/// Parses a single basic type.
fn parse_basic_type(
  basic_type: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(basic_type.BasicType, String) {
  use attribute_name <- result.try(gh.extract_string_from_node(
    basic_type,
    "attribute_name",
  ))

  // Get the attribute_type, return error if not specified
  use type_str <- result.try(gh.extract_string_from_node(
    basic_type,
    "attribute_type",
  ))

  let attribute_type = case type_str {
    "Boolean" -> Ok(accepted_types.Boolean)
    "Decimal" -> Ok(accepted_types.Decimal)
    "Integer" -> Ok(accepted_types.Integer)
    "String" -> Ok(accepted_types.String)
    _ -> {
      // Try to parse List or Optional types
      case string.split(type_str, on: "(") {
        ["List", inner_type_str] -> {
          // Remove the closing parenthesis and any whitespace
          let inner_type_name =
            inner_type_str
            |> string.slice(0, string.length(inner_type_str) - 1)
            |> string.trim()

          let inner_type = case inner_type_name {
            "Boolean" -> Ok(accepted_types.Boolean)
            "Decimal" -> Ok(accepted_types.Decimal)
            "Integer" -> Ok(accepted_types.Integer)
            "String" -> Ok(accepted_types.String)
            _ -> Error("Unknown attribute type: " <> inner_type_name)
          }
          case inner_type {
            Ok(inner_type) -> Ok(accepted_types.List(inner_type))
            Error(e) -> Error(e)
          }
        }
        ["Optional", inner_type_str] -> {
          // Remove the closing parenthesis and any whitespace
          let inner_type_name =
            inner_type_str
            |> string.slice(0, string.length(inner_type_str) - 1)
            |> string.trim()

          let inner_type = case inner_type_name {
            "Boolean" -> Ok(accepted_types.Boolean)
            "Decimal" -> Ok(accepted_types.Decimal)
            "Integer" -> Ok(accepted_types.Integer)
            "String" -> Ok(accepted_types.String)
            _ -> Error("Unknown attribute type: " <> inner_type_name)
          }
          case inner_type {
            Ok(inner_type) -> Ok(accepted_types.Optional(inner_type))
            Error(e) -> Error(e)
          }
        }
        _ -> Error("Unknown attribute type: " <> type_str)
      }
    }
  }

  // If there was an error parsing the attribute type, return it
  use attribute_type <- result.try(attribute_type)

  Ok(basic_type.BasicType(
    attribute_name: attribute_name,
    attribute_type: attribute_type,
  ))
}
