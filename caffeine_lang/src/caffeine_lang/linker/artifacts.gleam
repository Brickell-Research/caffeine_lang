import caffeine_lang/types.{type AcceptedTypes}
import gleam/dict

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
