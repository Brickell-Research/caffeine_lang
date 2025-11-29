import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import yay

pub opaque type Artifact {
  Artifact(
    name: String,
    version: String,
    base_params: dict.Dict(String, helpers.AcceptedTypes),
    params: dict.Dict(String, helpers.AcceptedTypes),
  )
}

pub fn make_artifact(
  name name: String,
  version version: String,
  base_params base_params: dict.Dict(String, helpers.AcceptedTypes),
  params params: dict.Dict(String, helpers.AcceptedTypes),
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

pub fn get_name(artifact: Artifact) -> String {
  artifact.name
}

pub fn get_base_params(
  artifact: Artifact,
) -> dict.Dict(String, helpers.AcceptedTypes) {
  artifact.base_params
}

pub fn get_params(
  artifact: Artifact,
) -> dict.Dict(String, helpers.AcceptedTypes) {
  artifact.params
}

/// Parses an artifact specification file into a list of artifacts.
pub fn parse(file_path: String) -> Result(List(Artifact), String) {
  use artifacts <- result.try(helpers.parse_specification(
    file_path,
    dict.new(),
    parse_artifact,
    "artifacts",
  ))

  helpers.validate_uniqueness(artifacts, fn(e) { e.name }, "artifact")
}

fn parse_artifact(
  type_node: yay.Node,
  _params: dict.Dict(String, String),
) -> Result(Artifact, String) {
  use name <- result.try(
    yay.extract_string_from_node(type_node, "name")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use version <- result.try(
    yay.extract_string_from_node(type_node, "version")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use base_params <- result.try(
    yay.extract_dict_strings_from_node(
      type_node,
      "base_params",
      fail_on_key_duplication: True,
    )
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    })
    |> result.try(helpers.dict_strings_to_accepted_types),
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

  Ok(Artifact(name:, version:, base_params:, params:))
}
