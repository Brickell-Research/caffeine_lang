import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/types/ast/basic_type
import glaml
import glaml_extended/helpers as glaml_extended_helpers
import gleam/dict
import gleam/result

// ==== Public ====
/// Given a specification file, returns a list of basic types.
pub fn parse_basic_types_specification(
  file_path: String,
) -> Result(List(basic_type.BasicType), String) {
  general_common.parse_specification(
    file_path,
    dict.new(),
    parse_basic_type,
    "basic_types",
  )
}

// ==== Private ====
/// Parses a single basic type.
fn parse_basic_type(
  basic_type: glaml.Node,
  _params: dict.Dict(String, String),
) -> Result(basic_type.BasicType, String) {
  use attribute_name <- result.try(
    glaml_extended_helpers.extract_string_from_node(
      basic_type,
      "attribute_name",
    ),
  )

  // Get the attribute_type, return error if not specified
  use type_str <- result.try(glaml_extended_helpers.extract_string_from_node(
    basic_type,
    "attribute_type",
  ))

  // Use the centralized type parser that handles all type combinations
  use attribute_type <- result.try(general_common.string_to_accepted_type(
    type_str,
  ))

  Ok(basic_type.BasicType(
    attribute_name: attribute_name,
    attribute_type: attribute_type,
  ))
}
