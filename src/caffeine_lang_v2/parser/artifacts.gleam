import caffeine_lang_v2/common
import glaml_extended
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub opaque type Artifact {
  Artifact(
    name: String,
    version: String,
    base_params: dict.Dict(String, common.AcceptedTypes),
    params: dict.Dict(String, common.AcceptedTypes),
  )
}

pub fn make_artifact(
  name name: String,
  version version: String,
  base_params base_params: dict.Dict(String, common.AcceptedTypes),
  params params: dict.Dict(String, common.AcceptedTypes),
) -> Result(Artifact, String) {
  let error_msg =
    "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received '"
    <> version
    <> "'."

  case string.split(version, ".") {
    [major, minor, patch] -> {
      use _ <- result.try(
        list.try_map([major, minor, patch], int.parse)
        |> result.replace_error(error_msg),
      )
      Ok(Artifact(name:, version:, base_params:, params:))
    }
    _ -> Error(error_msg)
  }
}

pub fn get_base_params(
  artifact: Artifact,
) -> dict.Dict(String, common.AcceptedTypes) {
  artifact.base_params
}

pub fn get_params(artifact: Artifact) -> dict.Dict(String, common.AcceptedTypes) {
  artifact.params
}

/// Parses an artifact specification file into a list of artifacts.
pub fn parse(file_path: String) -> Result(List(Artifact), String) {
  use artifacts <- result.try(common.parse_specification(
    file_path,
    dict.new(),
    parse_artifact,
    "artifacts",
  ))

  common.validate_uniqueness(artifacts, fn(e) { e.name }, "artifact")
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
