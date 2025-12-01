import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import yay

pub type Artifact {
  Artifact(
    name: AcceptedArtifactNames,
    version: Semver,
    base_params: dict.Dict(String, helpers.AcceptedTypes),
    params: dict.Dict(String, helpers.AcceptedTypes),
  )
}

/// For more sensible pattern matching.
/// TODO: expand when we support more than Datadog SLOs
pub type AcceptedArtifactNames {
  ServiceLevelObjective
}

pub fn string_to_artifact_name(
  name: String,
) -> Result(AcceptedArtifactNames, String) {
  case name |> string.lowercase {
    "slo" -> Ok(ServiceLevelObjective)
    _ -> Error("Unsupported artifact: " <> name <> ". Supported artifacts include: slo.")
  }
}

pub fn artifact_name_to_string(name: AcceptedArtifactNames) -> String {
  case name {
    ServiceLevelObjective -> "slo"
  }
}

pub opaque type Semver {
  Semver(major: Int, minor: Int, patch: Int)
}

pub fn make_semver(version version: String) -> Result(Semver, String) {
  case version |> string.split(".") |> list.try_map(int.parse) {
    Ok([major, minor, patch]) -> Ok(Semver(major:, minor:, patch:))
    _ ->
      Error(
        "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received '"
        <> version
        <> "'.",
      )
  }
}

pub fn make_artifact(
  name name: String,
  version version: String,
  base_params base_params: dict.Dict(String, helpers.AcceptedTypes),
  params params: dict.Dict(String, helpers.AcceptedTypes),
) -> Result(Artifact, String) {
  use semver <- result.try(make_semver(version:))

  use artifact_name <- result.try(string_to_artifact_name(name))

  Ok(Artifact(name: artifact_name, version: semver, base_params:, params:))
}

pub fn parse(file_path: String) -> Result(List(Artifact), String) {
  use artifacts <- result.try(helpers.parse_specification(
    file_path,
    dict.new(),
    parse_artifact,
    "artifacts",
  ))

  helpers.validate_uniqueness(
    artifacts,
    fn(e) { e.name |> artifact_name_to_string },
    "artifact",
  )
}

fn parse_artifact(
  type_node: yay.Node,
  _params: dict.Dict(String, String),
) -> Result(Artifact, String) {
  use string_name <- result.try(
    yay.extract_string(type_node, "name")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use name <- result.try(string_name |> string_to_artifact_name)

  use version_string <- result.try(
    yay.extract_string(type_node, "version")
    |> result.map_error(fn(extraction_error) {
      yay.extraction_error_to_string(extraction_error)
    }),
  )

  use version <- result.try(make_semver(version_string))

  use base_params <- result.try(
    yay.extract_string_map_with_duplicate_detection(
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

  Ok(Artifact(name:, version:, base_params:, params:))
}
