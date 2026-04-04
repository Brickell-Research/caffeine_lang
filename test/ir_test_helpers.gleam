/// Shared test helpers for constructing IntermediateRepresentation values.
import caffeine_lang/analysis/vendor
import caffeine_lang/helpers
import caffeine_lang/identifiers
import caffeine_lang/linker/artifacts.{Hard, Soft}
import caffeine_lang/linker/ir
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option

/// Creates an SLO IR with no dependency relations.
pub fn make_slo_ir(
  org: String,
  team: String,
  service: String,
  name: String,
  threshold threshold: Float,
) {
  let values = [
    helpers.ValueTuple(
      "vendor",
      types.PrimitiveType(types.String),
      value.StringValue("datadog"),
    ),
    helpers.ValueTuple(
      "threshold",
      types.PrimitiveType(types.NumericType(types.Float)),
      value.PercentageValue(threshold),
    ),
  ]
  ir.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    values: values,
    slo: make_test_slo_fields(threshold, dict.new()),
    vendor: option.Some(vendor.Datadog),
  )
}

/// Creates an IR with SLO and dependency relations.
pub fn make_ir_with_deps(
  org: String,
  team: String,
  service: String,
  name: String,
  hard_deps hard_deps: List(String),
  soft_deps soft_deps: List(String),
  threshold threshold: Float,
) {
  let values = [
    helpers.ValueTuple(
      "vendor",
      types.PrimitiveType(types.String),
      value.StringValue("datadog"),
    ),
    helpers.ValueTuple(
      "threshold",
      types.PrimitiveType(types.NumericType(types.Float)),
      value.PercentageValue(threshold),
    ),
    make_relations_value(hard_deps, soft_deps),
  ]
  let depends_on =
    option.Some(dict.from_list([#(Hard, hard_deps), #(Soft, soft_deps)]))
  ir.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    values: values,
    slo: make_test_slo_fields_with_deps(threshold, dict.new(), depends_on),
    vendor: option.Some(vendor.Datadog),
  )
}

/// Creates an SLO IR with dependency relations and a default threshold.
pub fn make_deps_only_ir(
  org: String,
  team: String,
  service: String,
  name: String,
  hard_deps hard_deps: List(String),
  soft_deps soft_deps: List(String),
) {
  let depends_on =
    option.Some(dict.from_list([#(Hard, hard_deps), #(Soft, soft_deps)]))
  ir.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    values: [
      make_relations_value(hard_deps, soft_deps),
    ],
    slo: make_test_slo_fields_with_deps(99.9, dict.new(), depends_on),
    vendor: option.Some(vendor.Datadog),
  )
}

/// Constructs test metadata with a fixed measurement name.
fn make_test_metadata(
  org: String,
  team: String,
  service: String,
  name: String,
) -> ir.IntermediateRepresentationMetaData {
  ir.IntermediateRepresentationMetaData(
    friendly_label: identifiers.ExpectationLabel(name),
    org_name: identifiers.OrgName(org),
    service_name: identifiers.ServiceName(service),
    measurement_name: identifiers.MeasurementName("test_measurement"),
    team_name: identifiers.TeamName(team),
    misc: dict.new(),
  )
}

/// Builds a unique identifier from org, service, and name.
fn make_unique_id(org: String, service: String, name: String) -> String {
  org <> "_" <> service <> "_" <> name
}

/// Builds the relations ValueTuple from hard and soft dependency lists.
fn make_relations_value(
  hard_deps: List(String),
  soft_deps: List(String),
) -> helpers.ValueTuple {
  let relations_value =
    value.DictValue(
      dict.from_list([
        #("hard", value.ListValue(hard_deps |> list.map(value.StringValue))),
        #("soft", value.ListValue(soft_deps |> list.map(value.StringValue))),
      ]),
    )

  helpers.ValueTuple(
    "relations",
    types.CollectionType(types.Dict(
      types.PrimitiveType(types.String),
      types.CollectionType(types.List(types.PrimitiveType(types.String))),
    )),
    relations_value,
  )
}

/// Creates an SLO IR for any vendor with full indicator and evaluation support.
pub fn make_vendor_slo_ir(
  friendly_label: String,
  unique_identifier: String,
  org: String,
  team: String,
  service: String,
  measurement: String,
  threshold: Float,
  window_in_days: Int,
  evaluation: String,
  indicators: List(#(String, String)),
  vendor_string: String,
  vendor_enum: vendor.Vendor,
) {
  ir.IntermediateRepresentation(
    metadata: ir.IntermediateRepresentationMetaData(
      friendly_label: identifiers.ExpectationLabel(friendly_label),
      org_name: identifiers.OrgName(org),
      service_name: identifiers.ServiceName(service),
      measurement_name: identifiers.MeasurementName(measurement),
      team_name: identifiers.TeamName(team),
      misc: dict.new(),
    ),
    unique_identifier: unique_identifier,
    values: [
      helpers.ValueTuple(
        "vendor",
        types.PrimitiveType(types.String),
        value.StringValue(vendor_string),
      ),
      helpers.ValueTuple(
        "threshold",
        types.PrimitiveType(types.NumericType(types.Float)),
        value.PercentageValue(threshold),
      ),
      helpers.ValueTuple(
        "window_in_days",
        types.PrimitiveType(types.NumericType(types.Integer)),
        value.IntValue(window_in_days),
      ),
      helpers.ValueTuple(
        "evaluation",
        types.PrimitiveType(types.String),
        value.StringValue(evaluation),
      ),
      helpers.ValueTuple(
        "indicators",
        types.CollectionType(types.Dict(
          types.PrimitiveType(types.String),
          types.PrimitiveType(types.String),
        )),
        value.DictValue(
          indicators
          |> list.map(fn(pair) { #(pair.0, value.StringValue(pair.1)) })
          |> dict.from_list,
        ),
      ),
    ],
    slo: ir.SloFields(
      threshold: threshold,
      indicators: indicators |> dict.from_list,
      window_in_days: window_in_days,
      evaluation: option.Some(evaluation),
      tags: [],
      runbook: option.None,
      depends_on: option.None,
    ),
    vendor: option.Some(vendor_enum),
  )
}

/// Builds default SloFields for tests with no dependencies.
fn make_test_slo_fields(
  threshold: Float,
  indicators: dict.Dict(String, String),
) -> ir.SloFields {
  ir.SloFields(
    threshold: threshold,
    indicators: indicators,
    window_in_days: 30,
    evaluation: option.None,
    tags: [],
    runbook: option.None,
    depends_on: option.None,
  )
}

/// Builds SloFields for tests with dependency relations.
fn make_test_slo_fields_with_deps(
  threshold: Float,
  indicators: dict.Dict(String, String),
  depends_on: option.Option(
    dict.Dict(artifacts.DependencyRelationType, List(String)),
  ),
) -> ir.SloFields {
  ir.SloFields(
    threshold: threshold,
    indicators: indicators,
    window_in_days: 30,
    evaluation: option.None,
    tags: [],
    runbook: option.None,
    depends_on: depends_on,
  )
}
