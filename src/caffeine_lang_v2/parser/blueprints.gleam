import caffeine_lang_v2/common
import glaml_extended
import gleam/dict
import gleam/result

pub opaque type Blueprint {
  Blueprint(
    name: String,
    artifact: String,
    params: dict.Dict(String, common.AcceptedTypes),
    inputs: dict.Dict(String, String),
  )
}

pub fn make_blueprint(
  name name: String,
  artifact artifact: String,
  params params: dict.Dict(String, common.AcceptedTypes),
  inputs inputs: dict.Dict(String, String),
) -> Blueprint {
  Blueprint(name:, artifact:, params:, inputs:)
}

pub fn get_name(blueprint: Blueprint) -> String {
  blueprint.name
}

pub fn get_artifact(blueprint: Blueprint) -> String {
  blueprint.artifact
}

pub fn get_params(
  blueprint: Blueprint,
) -> dict.Dict(String, common.AcceptedTypes) {
  blueprint.params
}

pub fn get_inputs(blueprint: Blueprint) -> dict.Dict(String, String) {
  blueprint.inputs
}

/// Parses a blueprint specification file into a list of blueprints.
pub fn parse(file_path: String) -> Result(List(Blueprint), String) {
  use blueprints <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_blueprint,
    "blueprints",
  ))

  common.validate_uniqueness(blueprints, fn(e) { e.name }, "blueprint")
}

fn parse_blueprint(
  type_node: glaml_extended.Node,
  _params: dict.Dict(String, String),
) -> Result(Blueprint, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "name",
  ))

  use artifact <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "artifact",
  ))

  use params <- result.try(
    glaml_extended.extract_dict_strings_from_node(
      type_node,
      "params",
      fail_on_key_duplication: True,
    )
    |> result.try(common.dict_strings_to_accepted_types),
  )

  use inputs <- result.try(glaml_extended.extract_dict_strings_from_node(
    type_node,
    "inputs",
    fail_on_key_duplication: True,
  ))

  Ok(Blueprint(name:, artifact:, params:, inputs:))
}
