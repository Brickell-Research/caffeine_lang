import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/result
import yay

pub opaque type Blueprint {
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

pub fn set_name(blueprint: Blueprint, name: String) -> Blueprint {
  Blueprint(..blueprint, name:)
}

pub fn get_name(blueprint: Blueprint) -> String {
  blueprint.name
}

pub fn set_artifact(blueprint: Blueprint, artifact: String) -> Blueprint {
  Blueprint(..blueprint, artifact:)
}

pub fn get_artifact(blueprint: Blueprint) -> String {
  blueprint.artifact
}

pub fn get_params(
  blueprint: Blueprint,
) -> dict.Dict(String, helpers.AcceptedTypes) {
  blueprint.params
}

pub fn set_params(
  blueprint: Blueprint,
  params: dict.Dict(String, helpers.AcceptedTypes),
) -> Blueprint {
  Blueprint(..blueprint, params:)
}

pub fn set_inputs(
  blueprint: Blueprint,
  inputs: dict.Dict(String, String),
) -> Blueprint {
  Blueprint(..blueprint, inputs:)
}

pub fn get_inputs(blueprint: Blueprint) -> dict.Dict(String, String) {
  blueprint.inputs
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
    yay.extract_string_from_node(type_node, "name")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use artifact <- result.try(
    yay.extract_string_from_node(type_node, "artifact")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use params <- result.try(
    yay.extract_dict_strings_from_node(
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
    yay.extract_dict_strings_from_node(
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
