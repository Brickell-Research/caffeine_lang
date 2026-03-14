/// Core IR types for the Caffeine compiler pipeline.
/// These types represent the intermediate representation between linking and code generation.
/// The phantom type parameter `phase` tracks pipeline progress at the type level.
import caffeine_lang/analysis/vendor.{type Vendor}
import caffeine_lang/helpers.{type ValueTuple}
import caffeine_lang/identifiers.{
  type BlueprintName, type ExpectationLabel, type OrgName, type ServiceName,
  type TeamName,
}
import caffeine_lang/linker/artifacts.{type ArtifactType, type DependencyRelationType, SLO}
import gleam/dict
import gleam/option.{type Option}

/// Marker type for IRs freshly built by the linker.
pub type Linked

/// Marker type for IRs with validated dependencies.
pub type DepsValidated

/// Marker type for IRs with resolved indicators.
pub type Resolved

/// Structured SLO artifact fields extracted from raw values.
pub type SloFields {
  SloFields(
    threshold: Float,
    indicators: dict.Dict(String, String),
    window_in_days: Int,
    evaluation: Option(String),
    tags: List(#(String, String)),
    runbook: Option(String),
    depends_on: Option(dict.Dict(DependencyRelationType, List(String))),
  )
}

/// Artifact-specific data stored as a dict from artifact type to fields.
pub type ArtifactData {
  ArtifactData(fields: dict.Dict(ArtifactType, ArtifactFields))
}

/// Wrapper for artifact-specific field data.
pub type ArtifactFields {
  SloArtifactFields(SloFields)
}

/// Internal representation of a parsed expectation with metadata and values.
/// The phantom type parameter `phase` tracks pipeline progress:
/// - `Linked`: freshly built by the linker
/// - `DepsValidated`: dependencies have been validated
/// - `Resolved`: indicators have been resolved by semantic analysis
pub type IntermediateRepresentation(phase) {
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
/// Fields use newtype wrappers to prevent accidental mixing of identifier kinds.
pub type IntermediateRepresentationMetaData {
  IntermediateRepresentationMetaData(
    friendly_label: ExpectationLabel,
    org_name: OrgName,
    service_name: ServiceName,
    blueprint_name: BlueprintName,
    team_name: TeamName,
    /// Metadata specific to any given expectation.
    misc: dict.Dict(String, List(String)),
  )
}

/// Promotes an IR to a new phantom phase by reconstructing all fields.
@internal
pub fn promote(
  ir: IntermediateRepresentation(a),
) -> IntermediateRepresentation(b) {
  IntermediateRepresentation(
    metadata: ir.metadata,
    unique_identifier: ir.unique_identifier,
    artifact_refs: ir.artifact_refs,
    values: ir.values,
    artifact_data: ir.artifact_data,
    vendor: ir.vendor,
  )
}

/// Build a dotted identifier from IR metadata: org.team.service.name.
@internal
pub fn ir_to_identifier(ir: IntermediateRepresentation(phase)) -> String {
  ir.metadata.org_name.value
  <> "."
  <> ir.metadata.team_name.value
  <> "."
  <> ir.metadata.service_name.value
  <> "."
  <> ir.metadata.friendly_label.value
}

/// Extract SloFields from ArtifactData, if present.
@internal
pub fn get_slo_fields(data: ArtifactData) -> Option(SloFields) {
  case dict.get(data.fields, SLO) {
    Ok(SloArtifactFields(slo)) -> option.Some(slo)
    _ -> option.None
  }
}

/// Creates ArtifactData containing SLO fields.
@internal
pub fn slo_only(slo: SloFields) -> ArtifactData {
  ArtifactData(fields: dict.from_list([#(SLO, SloArtifactFields(slo))]))
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
