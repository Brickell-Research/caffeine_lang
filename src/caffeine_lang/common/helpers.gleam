import caffeine_lang/common/errors.{type CompilationError, ParserFileReadError}
import gleam/dynamic.{type Dynamic}
import gleam/list
import simplifile

/// AcceptedTypes is a union of all the types that can be used as filters. It is recursive
/// to allow for nested filters. This may be a bug in the future since it seems it may
/// infinitely recurse.
pub type AcceptedTypes {
  Boolean
  Float
  Integer
  String
  Dict(AcceptedTypes, AcceptedTypes)
  List(AcceptedTypes)
  Optional(AcceptedTypes)
  /// Defaulted type stores the inner type and its default value as a string
  /// e.g., Defaulted(Integer, "10") means an optional integer with default 10
  Defaulted(AcceptedTypes, String)
}

/// A tuple of a label, type, and value used for template resolution.
pub type ValueTuple {
  ValueTuple(label: String, typ: AcceptedTypes, value: Dynamic)
}

/// Converts an AcceptedTypes to its string representation.
pub fn accepted_type_to_string(accepted_type: AcceptedTypes) -> String {
  case accepted_type {
    Boolean -> "Boolean"
    Float -> "Float"
    Integer -> "Integer"
    String -> "String"
    Dict(key_type, value_type) ->
      "Dict("
      <> accepted_type_to_string(key_type)
      <> ", "
      <> accepted_type_to_string(value_type)
      <> ")"
    List(inner_type) -> "List(" <> accepted_type_to_string(inner_type) <> ")"
    Optional(inner_type) ->
      "Optional(" <> accepted_type_to_string(inner_type) <> ")"
    Defaulted(inner_type, default_val) ->
      "Defaulted("
      <> accepted_type_to_string(inner_type)
      <> ", "
      <> default_val
      <> ")"
  }
}

/// Reads the contents of a JSON file as a string.
pub fn json_from_file(file_path) -> Result(String, CompilationError) {
  case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(ParserFileReadError(
        msg: simplifile.describe_error(err) <> " (" <> file_path <> ")",
      ))
  }
}

/// A helper for chaining Result operations with the `use` syntax.
/// Equivalent to `result.try` but defined here for convenient use with `use`.
pub fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}

/// Maps each referrer to its corresponding reference by matching names.
/// Returns a list of tuples pairing each referrer with its matched reference.
pub fn map_reference_to_referrer_over_collection(
  references references: List(a),
  referrers referrers: List(b),
  reference_name reference_name: fn(a) -> String,
  referrer_reference referrer_reference: fn(b) -> String,
) {
  referrers
  |> list.map(fn(referrer) {
    // already performed this check so can assert it
    let assert Ok(reference) =
      references
      |> list.filter(fn(reference) {
        { reference |> reference_name } == { referrer |> referrer_reference }
      })
      |> list.first
    #(referrer, reference)
  })
}
