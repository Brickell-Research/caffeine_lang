/// Shared test helpers for constructing IntermediateRepresentation values.
import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/helpers
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
) -> semantic_analyzer.IntermediateRepresentation {
  semantic_analyzer.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    artifact_refs: ["SLO"],
    values: [
      helpers.ValueTuple(
        "vendor",
        types.PrimitiveType(types.String),
        value.StringValue("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        types.PrimitiveType(types.NumericType(types.Float)),
        value.FloatValue(threshold),
      ),
    ],
    vendor: option.Some(vendor.Datadog),
  )
}

/// Creates an IR with SLO and DependencyRelations artifacts.
pub fn make_ir_with_deps(
  org: String,
  team: String,
  service: String,
  name: String,
  hard_deps hard_deps: List(String),
  soft_deps soft_deps: List(String),
  threshold threshold: Float,
) -> semantic_analyzer.IntermediateRepresentation {
  semantic_analyzer.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    artifact_refs: ["SLO", "DependencyRelations"],
    values: [
      helpers.ValueTuple(
        "vendor",
        types.PrimitiveType(types.String),
        value.StringValue("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        types.PrimitiveType(types.NumericType(types.Float)),
        value.FloatValue(threshold),
      ),
      make_relations_value(hard_deps, soft_deps),
    ],
    vendor: option.Some(vendor.Datadog),
  )
}

/// Creates an IR with DependencyRelations only (no SLO artifact).
pub fn make_deps_only_ir(
  org: String,
  team: String,
  service: String,
  name: String,
  hard_deps hard_deps: List(String),
  soft_deps soft_deps: List(String),
) -> semantic_analyzer.IntermediateRepresentation {
  semantic_analyzer.IntermediateRepresentation(
    metadata: make_test_metadata(org, team, service, name),
    unique_identifier: make_unique_id(org, service, name),
    artifact_refs: ["DependencyRelations"],
    values: [
      make_relations_value(hard_deps, soft_deps),
    ],
    vendor: option.None,
  )
}

/// Constructs test metadata with a fixed blueprint name.
fn make_test_metadata(
  org: String,
  team: String,
  service: String,
  name: String,
) -> semantic_analyzer.IntermediateRepresentationMetaData {
  semantic_analyzer.IntermediateRepresentationMetaData(
    friendly_label: name,
    org_name: org,
    service_name: service,
    blueprint_name: "test_blueprint",
    team_name: team,
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
