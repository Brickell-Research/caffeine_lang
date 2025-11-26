import glaml_extended
import gleam/dict
import gleam/result

// ==== Public ====

/// Parses a specification file into a list of glaml documents according to the given parse function.
pub fn parse_specification(
  file_path: String,
  params: dict.Dict(String, String),
  parse_fn: fn(glaml_extended.Node, dict.Dict(String, String)) ->
    Result(a, String),
  key: String,
) -> Result(List(a), String) {
  // TODO: consider enforcing constraints on file path, however for now, unnecessary.

  // parse the YAML file
  use doc <- result.try(
    glaml_extended.parse_file(file_path)
    |> result.map_error(fn(_) { "Failed to parse YAML file: " <> file_path }),
  )
  let parse_fn_two = fn(doc, _params) {
    glaml_extended.iteratively_parse_collection(
      glaml_extended.document_root(doc),
      params,
      parse_fn,
      key,
    )
  }

  // parse the intermediate representation, here just the sli_types
  case doc {
    [first, ..] -> parse_fn_two(first, params)
    _ -> Error("Empty YAML file: " <> file_path)
  }
}
