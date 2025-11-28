import caffeine_lang_v2/common
import glaml_extended
import gleam/dict
import gleam/result

pub type Artifact {
  Artifact(
    name: String,
    version: String,
    // TODO: make this an opaque type in order to enforce correct formatting
    base_params: dict.Dict(String, common.AcceptedTypes),
    params: dict.Dict(String, common.AcceptedTypes),
  )
}

/// Parses an artifact specification file into a list of artifacts.
pub fn parse(file_path: String) -> Result(List(Artifact), String) {
  use artifacts <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_artifact,
    "artifacts",
  ))

  common.validate_uniqueness(artifacts, fn(e) { e.name })
}

fn parse_artifact(
  type_node: glaml_extended.Node,
  _params: dict.Dict(String, String),
) -> Result(Artifact, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "name",
  ))

  use version <- result.try(glaml_extended.extract_string_from_node(
    type_node,
    "version",
  ))

  use base_params <- result.try(
    glaml_extended.extract_dict_strings_from_node(
      type_node,
      "base_params",
      fail_on_key_duplication: True,
    )
    |> result.try(common.dict_strings_to_accepted_types),
  )

  use params <- result.try(
    glaml_extended.extract_dict_strings_from_node(
      type_node,
      "params",
      fail_on_key_duplication: True,
    )
    |> result.try(common.dict_strings_to_accepted_types),
  )

  Ok(Artifact(name:, version:, base_params:, params:))
}
