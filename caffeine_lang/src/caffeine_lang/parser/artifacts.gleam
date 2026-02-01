import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/modifier_types
import caffeine_lang/common/refinement_types
import gleam/dict
import gleam/list
import gleam/string
import gleam_community/ansi

/// Information about a parameter including its type and description.
pub type ParamInfo {
  ParamInfo(type_: AcceptedTypes, description: String)
}

/// A reusable artifact template with named parameters.
pub type Artifact {
  Artifact(
    type_: ArtifactType,
    description: String,
    params: dict.Dict(String, ParamInfo),
  )
}

/// Types of supported artifacts.
pub type ArtifactType {
  SLO
  DependencyRelations
}

/// Extracts just the types from artifact params, discarding descriptions.
/// Useful when downstream code only needs type information.
@internal
pub fn params_to_types(
  params: dict.Dict(String, ParamInfo),
) -> dict.Dict(String, AcceptedTypes) {
  params
  |> dict.map_values(fn(_, param_info) { param_info.type_ })
}

/// Converts an ArtifactType to its corresponding string representation.
@internal
pub fn artifact_type_to_string(type_: ArtifactType) -> String {
  case type_ {
    SLO -> "SLO"
    DependencyRelations -> "DependencyRelations"
  }
}

/// Pretty-prints an artifact showing its type, description, and parameters.
@internal
pub fn pretty_print_artifact(artifact: Artifact) -> String {
  let header =
    ansi.bold(ansi.cyan(artifact_type_to_string(artifact.type_)))
    <> ": "
    <> ansi.dim("\"" <> artifact.description <> "\"")
  let params =
    artifact.params
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let #(name, param_info) = pair
      "  "
      <> ansi.yellow(name)
      <> ": "
      <> ansi.dim("\"" <> param_info.description <> "\"")
      <> "\n    type: "
      <> ansi.green(accepted_types.accepted_type_to_string(param_info.type_))
      <> "\n    "
      <> param_status(param_info.type_)
    })
    |> string.join("\n")

  header <> "\n\n" <> params
}

/// Returns the status of a parameter: "required", "optional", or "default: <value>".
@internal
pub fn param_status(typ: AcceptedTypes) -> String {
  case typ {
    accepted_types.ModifierType(modifier_types.Optional(_)) ->
      ansi.dim("optional")
    accepted_types.ModifierType(modifier_types.Defaulted(_, default)) ->
      ansi.blue("default: " <> default)
    accepted_types.RefinementType(refinement_types.OneOf(inner, _)) ->
      param_status(inner)
    _ -> ansi.magenta("required")
  }
}
