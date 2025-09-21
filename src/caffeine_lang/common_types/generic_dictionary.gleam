import caffeine_lang/common_types/accepted_types.{type AcceptedTypes}
import gleam/dict
import gleam/result

/// A dictionary that stores typed values
pub type GenericDictionary {
  GenericDictionary(entries: dict.Dict(String, TypedValue))
}

/// A value with its type information
pub type TypedValue {
  TypedValue(value: String, type_def: AcceptedTypes)
}

/// Creates a new empty GenericDictionary
pub fn new() -> GenericDictionary {
  GenericDictionary(entries: dict.new())
}

/// Creates a new typed value
pub fn new_typed_value(value: String, type_def: AcceptedTypes) -> TypedValue {
  TypedValue(value: value, type_def: type_def)
}

/// Creates a new GenericDictionary from string values and their type definitions
pub fn from_string_dict(
  values: dict.Dict(String, String),
  type_defs: dict.Dict(String, AcceptedTypes),
) -> Result(GenericDictionary, String) {
  let result_dict = dict.new()

  let insert_typed = fn(acc, key, value) {
    case dict.get(type_defs, key) {
      Ok(type_def) -> {
        dict.insert(acc, key, new_typed_value(value, type_def))
      }
      Error(_) -> acc
      // Skip keys without type definitions
    }
  }

  let entries = dict.fold(values, result_dict, insert_typed)
  Ok(GenericDictionary(entries: entries))
}

/// Gets a typed value from the dictionary
pub fn get(dict: GenericDictionary, key: String) -> Result(TypedValue, String) {
  dict.entries
  |> dict.get(key)
  |> result.replace_error("Key not found: " <> key)
}

/// Gets the string value from a TypedValue
pub fn get_string_value(typed_value: TypedValue) -> String {
  typed_value.value
}

/// Gets the type definition from a TypedValue
pub fn get_type_definition(typed_value: TypedValue) -> AcceptedTypes {
  typed_value.type_def
}

/// Converts a GenericDictionary to a regular dict of strings
pub fn to_string_dict(dict: GenericDictionary) -> dict.Dict(String, String) {
  let extract_value = fn(_key: String, typed_value: TypedValue) -> String {
    typed_value.value
  }
  dict.entries
  |> dict.map_values(extract_value)
}
