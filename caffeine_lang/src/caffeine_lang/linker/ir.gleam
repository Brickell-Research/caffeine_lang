/// Core IR types for the Caffeine compiler pipeline.
/// These types represent the intermediate representation between linking and code generation.
import caffeine_lang/analysis/vendor.{type Vendor}
import caffeine_lang/helpers.{type ValueTuple}
import caffeine_lang/linker/artifacts.{
  type ArtifactType, type DependencyRelationType, DependencyRelations, SLO,
}
import gleam/dict
import gleam/option.{type Option}

/// Structured SLO artifact fields extracted from raw values.
pub type SloFields {
  SloFields(
    threshold: Float,
    indicators: dict.Dict(String, String),
    window_in_days: Int,
    evaluation: Option(String),
    tags: List(#(String, String)),
    runbook: Option(String),
  )
}

/// Structured dependency artifact fields extracted from raw values.
pub type DependencyFields {
  DependencyFields(
    relations: dict.Dict(DependencyRelationType, List(String)),
    tags: List(#(String, String)),
  )
}

/// Artifact-specific data stored as a dict from artifact type to fields.
pub type ArtifactData {
  ArtifactData(fields: dict.Dict(ArtifactType, ArtifactFields))
}

/// Wrapper for artifact-specific field data.
pub type ArtifactFields {
  SloArtifactFields(SloFields)
  DependencyArtifactFields(DependencyFields)
}

/// Internal representation of a parsed expectation with metadata and values.
pub type IntermediateRepresentation {
  IntermediateRepresentation(
    metadata: IntermediateRepresentationMetaData,
    unique_identifier: String,
    artifact_refs: List(ArtifactType),
    values: List(ValueTuple),
    artifact_data: ArtifactData,
    vendor: Option(Vendor),
  )
}

/// Metadata associated with an intermediate representation including organization and service identifiers.
pub type IntermediateRepresentationMetaData {
  IntermediateRepresentationMetaData(
    friendly_label: String,
    org_name: String,
    service_name: String,
    blueprint_name: String,
    team_name: String,
    /// Metadata specific to any given expectation.
    misc: dict.Dict(String, List(String)),
  )
}

/// Build a dotted identifier from IR metadata: org.team.service.name
@internal
pub fn ir_to_identifier(ir: IntermediateRepresentation) -> String {
  ir.metadata.org_name
  <> "."
  <> ir.metadata.team_name
  <> "."
  <> ir.metadata.service_name
  <> "."
  <> ir.metadata.friendly_label
}

/// Extract SloFields from ArtifactData, if present.
@internal
pub fn get_slo_fields(data: ArtifactData) -> Option(SloFields) {
  case dict.get(data.fields, SLO) {
    Ok(SloArtifactFields(slo)) -> option.Some(slo)
    _ -> option.None
  }
}

/// Extract DependencyFields from ArtifactData, if present.
@internal
pub fn get_dependency_fields(data: ArtifactData) -> Option(DependencyFields) {
  case dict.get(data.fields, DependencyRelations) {
    Ok(DependencyArtifactFields(dep)) -> option.Some(dep)
    _ -> option.None
  }
}

/// Creates ArtifactData containing only SLO fields.
@internal
pub fn slo_only(slo: SloFields) -> ArtifactData {
  ArtifactData(fields: dict.from_list([#(SLO, SloArtifactFields(slo))]))
}

/// Creates ArtifactData containing only dependency fields.
@internal
pub fn dependency_only(dep: DependencyFields) -> ArtifactData {
  ArtifactData(
    fields: dict.from_list([
      #(DependencyRelations, DependencyArtifactFields(dep)),
    ]),
  )
}

/// Creates ArtifactData containing both SLO and dependency fields.
@internal
pub fn slo_with_dependency(
  slo slo: SloFields,
  dependency dep: DependencyFields,
) -> ArtifactData {
  ArtifactData(
    fields: dict.from_list([
      #(SLO, SloArtifactFields(slo)),
      #(DependencyRelations, DependencyArtifactFields(dep)),
    ]),
  )
}

/// Update SloFields within ArtifactData using a transformation function.
@internal
pub fn update_slo_fields(
  data: ArtifactData,
  updater: fn(SloFields) -> SloFields,
) -> ArtifactData {
  case dict.get(data.fields, SLO) {
    Ok(SloArtifactFields(slo)) ->
      ArtifactData(fields: dict.insert(
        data.fields,
        SLO,
        SloArtifactFields(updater(slo)),
      ))
    _ -> data
  }
}
