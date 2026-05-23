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
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option.{type Option}

/// Marker type for IRs freshly built by the linker.
pub type Linked

/// Marker type for IRs with validated dependencies.
pub type DepsValidated

/// Marker type for IRs with resolved indicators.
pub type Resolved

/// An indicator's source — either an inline query string (the existing form)
/// or an external signal contract that the relay materializes into a metric
/// the vendor codegen then queries.
///
/// `LiteralQuery` carries a query string (e.g. `"sum:requests{...}"`) with
/// possible `$$var$$` template variables; this is the pre-`6.x` shape.
///
/// `ExternalSignal` carries the routing info for a runtime relay (Langfuse
/// today). At codegen time the DD pipeline rewrites it into a `LiteralQuery`
/// referencing a synthesized metric name (`caffeine.<measurement>.<indicator>`),
/// and the relay codegen emits a matching entry in `signals.json`.
pub type IndicatorSource {
  LiteralQuery(query: String)
  ExternalSignal(
    source: String,
    match: dict.Dict(String, value.Value),
    value_extraction: Option(ExternalValueExtraction),
  )
}

/// Resolved value-extraction spec on an `ExternalSignal` indicator. `path` is
/// the dotted path into the source event (e.g. "value" for a Langfuse score's
/// numeric value); `type_` is the resolved type constraint the extracted
/// value must satisfy.
pub type ExternalValueExtraction {
  ExternalValueExtraction(path: String, type_: AcceptedTypes)
}

/// Structured SLO artifact fields extracted from raw values.
///
/// `description` is the SLO description text (sourced from `###` doc comments
/// preceding the expectation in the source file). Datadog codegen renders it
/// into the `description` attribute, optionally combined with the runbook link.
pub type SloFields {
  SloFields(
    threshold: Float,
    indicators: dict.Dict(String, IndicatorSource),
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

/// Build an `IndicatorSource` dict from a list of `(name, literal_query)`
/// pairs. Drop-in replacement for `dict.from_list` at SloFields construction
/// sites that produce only literal queries (which today is everything except
/// future external-signal cases). Tests and ir_builder use this to avoid
/// open-coding the LiteralQuery wrap.
@internal
pub fn literal_indicators_from(
  pairs: List(#(String, String)),
) -> dict.Dict(String, IndicatorSource) {
  pairs
  |> list.map(fn(p) { #(p.0, LiteralQuery(p.1)) })
  |> dict.from_list
}
