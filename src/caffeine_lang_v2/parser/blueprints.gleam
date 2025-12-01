import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/result
import yay

pub type Blueprint {
  Blueprint(
    name: String,
    artifact: String,
    params: dict.Dict(String, helpers.AcceptedTypes),
    inputs: dict.Dict(String, String),
  )
}

pub fn make_blueprint(
  name name: String,
  artifact artifact: String,
  params params: dict.Dict(String, helpers.AcceptedTypes),
  inputs inputs: dict.Dict(String, String),
) -> Blueprint {
  Blueprint(name:, artifact:, params:, inputs:)
}

/// Parses a blueprint specification file into a list of blueprints.
pub fn parse(file_path: String) -> Result(List(Blueprint), String) {
  use blueprints <- result.try(helpers.parse_specification(
    file_path,
    dict.new(),
    parse_blueprint,
    "blueprints",
  ))

  helpers.validate_uniqueness(blueprints, fn(e) { e.name }, "blueprint")
}

fn parse_blueprint(
  type_node: yay.Node,
  _params: dict.Dict(String, String),
) -> Result(Blueprint, String) {
  use name <- result.try(
    yay.extract_string(type_node, "name")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use artifact <- result.try(
    yay.extract_string(type_node, "artifact")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use params <- result.try(
    yay.extract_string_map_with_duplicate_detection(
      type_node,
      "params",
      fail_on_key_duplication: True,
    )
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    })
    |> result.try(helpers.dict_strings_to_accepted_types),
  )

  use inputs <- result.try(
    yay.extract_string_map_with_duplicate_detection(
      type_node,
      "inputs",
      fail_on_key_duplication: True,
    )
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  Ok(Blueprint(name:, artifact:, params:, inputs:))
}
