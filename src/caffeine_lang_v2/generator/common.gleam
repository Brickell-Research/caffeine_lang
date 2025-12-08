import caffeine_lang_v2/common/errors.{
  type GeneratorError, MissingValue, TypeError,
}
import caffeine_lang_v2/common/helpers.{type AcceptedTypes}
import caffeine_lang_v2/middle_end.{type IntermediateRepresentation, type ValueTuple}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Find a ValueTuple by label in an IntermediateRepresentation
pub fn find_value(
  ir: IntermediateRepresentation,
  key: String,
) -> Result(ValueTuple, GeneratorError) {
  ir.values
  |> list.find(fn(vt) { vt.label == key })
  |> result.replace_error(MissingValue(key))
}

/// Extract a String value from an IntermediateRepresentation
pub fn get_string_value(
  ir: IntermediateRepresentation,
  key: String,
) -> Result(String, GeneratorError) {
  use vt <- result.try(find_value(ir, key))

  case vt.typ {
    helpers.String ->
      case decode.run(vt.value, decode.string) {
        Ok(s) -> Ok(s)
        Error(_) -> Error(TypeError(key, "String", "invalid dynamic"))
      }
    other -> Error(TypeError(key, "String", accepted_type_to_string(other)))
  }
}

/// Extract a Float value from an IntermediateRepresentation
pub fn get_float_value(
  ir: IntermediateRepresentation,
  key: String,
) -> Result(Float, GeneratorError) {
  use vt <- result.try(find_value(ir, key))

  case vt.typ {
    helpers.Float ->
      case decode.run(vt.value, decode.float) {
        Ok(f) -> Ok(f)
        Error(_) -> Error(TypeError(key, "Float", "invalid dynamic"))
      }
    other -> Error(TypeError(key, "Float", accepted_type_to_string(other)))
  }
}

/// Extract an Int value from an IntermediateRepresentation
pub fn get_int_value(
  ir: IntermediateRepresentation,
  key: String,
) -> Result(Int, GeneratorError) {
  use vt <- result.try(find_value(ir, key))

  case vt.typ {
    helpers.Integer ->
      case decode.run(vt.value, decode.int) {
        Ok(i) -> Ok(i)
        Error(_) -> Error(TypeError(key, "Integer", "invalid dynamic"))
      }
    other -> Error(TypeError(key, "Integer", accepted_type_to_string(other)))
  }
}

/// Extract a Dict(String, String) value from an IntermediateRepresentation
pub fn get_string_dict_value(
  ir: IntermediateRepresentation,
  key: String,
) -> Result(Dict(String, String), GeneratorError) {
  use vt <- result.try(find_value(ir, key))

  case vt.typ {
    helpers.Dict(helpers.String, helpers.String) ->
      case decode.run(vt.value, decode.dict(decode.string, decode.string)) {
        Ok(d) -> Ok(d)
        Error(_) ->
          Error(TypeError(key, "Dict(String, String)", "invalid dynamic"))
      }
    other ->
      Error(TypeError(key, "Dict(String, String)", accepted_type_to_string(other)))
  }
}

/// Convert AcceptedTypes to a string representation
pub fn accepted_type_to_string(typ: AcceptedTypes) -> String {
  case typ {
    helpers.Boolean -> "Boolean"
    helpers.Float -> "Float"
    helpers.Integer -> "Integer"
    helpers.String -> "String"
    helpers.Dict(k, v) ->
      "Dict(" <> accepted_type_to_string(k) <> ", " <> accepted_type_to_string(v) <> ")"
    helpers.List(inner) -> "List(" <> accepted_type_to_string(inner) <> ")"
  }
}

/// Sanitize a name to be a valid Terraform resource identifier
/// Terraform identifiers must start with a letter or underscore and contain only
/// letters, digits, underscores, and hyphens
pub fn sanitize_resource_name(name: String) -> String {
  name
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(char) {
    case is_valid_identifier_char(char) {
      True -> char
      False -> "_"
    }
  })
  |> string.join("")
  |> ensure_starts_with_letter_or_underscore
}

fn is_valid_identifier_char(char: String) -> Bool {
  case char {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" -> True
    "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" -> True
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "_" | "-" -> True
    _ -> False
  }
}

fn ensure_starts_with_letter_or_underscore(name: String) -> String {
  case string.first(name) {
    Ok(first) ->
      case is_letter_or_underscore(first) {
        True -> name
        False -> "_" <> name
      }
    Error(_) -> "_empty"
  }
}

fn is_letter_or_underscore(char: String) -> Bool {
  case char {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" -> True
    "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" -> True
    "_" -> True
    _ -> False
  }
}

/// Convert window_in_days to Datadog timeframe string
pub fn days_to_timeframe(days: Int) -> String {
  case days {
    7 -> "7d"
    30 -> "30d"
    90 -> "90d"
    _ -> int.to_string(days) <> "d"
  }
}

/// Format a float as a string suitable for Terraform
pub fn float_to_string(f: Float) -> String {
  float.to_string(f)
}
