/// Core IR types for the Caffeine compiler pipeline.
/// These types represent the intermediate representation between linking and code generation.
/// The phantom type parameter `phase` tracks pipeline progress at the type level.
import caffeine_lang/analysis/vendor.{type Vendor}
import caffeine_lang/frontend/ast
import caffeine_lang/helpers.{type ValueTuple}
import caffeine_lang/identifiers.{
  type ExpectationLabel, type MeasurementName, type OrgName, type ServiceName,
  type TeamName,
}
import caffeine_lang/linker/dependency.{type DependencyRelationType}
import gleam/dict
import gleam/option.{type Option}

/// Marker type for IRs freshly built by the linker.
pub type Linked

/// Marker type for IRs with validated dependencies.
pub type DepsValidated

/// Marker type for IRs with resolved indicators.
pub type Resolved

/// Structured SLO artifact fields extracted from raw values.
///
/// `description` is the SLO description text (sourced from `###` doc comments
/// preceding the expectation in the source file). Datadog codegen renders it
/// into the `description` attribute, optionally combined with the runbook link.
pub type SloFields {
  SloFields(
    threshold: Float,
    indicators: dict.Dict(String, String),
    window_in_days: Int,
    evaluation: Option(String),
    tags: List(#(String, String)),
    runbook: Option(String),
    depends_on: Option(dict.Dict(DependencyRelationType, List(String))),
    description: Option(String),
    /// Latency threshold in milliseconds, sourced from a `Guarantees N% below
    /// <duration>` clause. Valid only on `time_slice`-shaped SLOs; codegen
    /// errors if present on a metric SLO.
    below_ms: Option(Float),
    /// Declared SLO type from the measurement header (`success_rate` or
    /// `time_slice`). None when the measurement uses the legacy untyped header
    /// — semantic checks that need the type (E10 alignment, F13 latency
    /// monotonicity) skip pairs where either side is None.
    expectation_type: Option(ast.ExpectationType),
  )
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
    values: List(ValueTuple),
    slo: SloFields,
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
    measurement_name: MeasurementName,
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
    values: ir.values,
    slo: ir.slo,
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

/// Update SloFields within an IR using a transformation function.
@internal
pub fn map_slo(
  ir: IntermediateRepresentation(a),
  updater: fn(SloFields) -> SloFields,
) -> IntermediateRepresentation(a) {
  IntermediateRepresentation(..ir, slo: updater(ir.slo))
}
