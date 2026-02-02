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

/// Parses a string into an ArtifactType, returning Error(Nil) for unknown types.
@internal
pub fn parse_artifact_type(raw: String) -> Result(ArtifactType, Nil) {
  case raw {
    "SLO" -> Ok(SLO)
    "DependencyRelations" -> Ok(DependencyRelations)
    _ -> Error(Nil)
  }
}

/// Types of dependency relationships between expectations.
pub type DependencyRelationType {
  /// If dependency down, dependent down.
  Hard
  /// Dependent can continue operating, either unscathed or within a degraded state if deendency down.
  Soft
}

/// Parses a string into a DependencyRelationType, returning Error(Nil) for unknown types.
@internal
pub fn parse_relation_type(s: String) -> Result(DependencyRelationType, Nil) {
  case s {
    "hard" -> Ok(Hard)
    "soft" -> Ok(Soft)
    _ -> Error(Nil)
  }
}

/// Converts a DependencyRelationType to its string representation.
@internal
pub fn relation_type_to_string(rt: DependencyRelationType) -> String {
  case rt {
    Hard -> "hard"
    Soft -> "soft"
  }
}
