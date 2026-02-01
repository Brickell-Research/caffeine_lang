/// Shared test helpers for constructing IntermediateRepresentation values.
import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/helpers
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
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
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: name,
      org_name: org,
      service_name: service,
      blueprint_name: "test_blueprint",
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: org <> "_" <> service <> "_" <> name,
    artifact_refs: ["SLO"],
    values: [
      helpers.ValueTuple(
        "vendor",
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        dynamic.float(threshold),
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
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: name,
      org_name: org,
      service_name: service,
      blueprint_name: "test_blueprint",
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: org <> "_" <> service <> "_" <> name,
    artifact_refs: ["SLO", "DependencyRelations"],
    values: [
      helpers.ValueTuple(
        "vendor",
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        dynamic.float(threshold),
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
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: name,
      org_name: org,
      service_name: service,
      blueprint_name: "test_blueprint",
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: org <> "_" <> service <> "_" <> name,
    artifact_refs: ["DependencyRelations"],
    values: [
      make_relations_value(hard_deps, soft_deps),
    ],
    vendor: option.None,
  )
}

/// Builds the relations ValueTuple from hard and soft dependency lists.
fn make_relations_value(
  hard_deps: List(String),
  soft_deps: List(String),
) -> helpers.ValueTuple {
  let relations_value =
    dynamic.properties([
      #(
        dynamic.string("hard"),
        dynamic.list(hard_deps |> list.map(dynamic.string)),
      ),
      #(
        dynamic.string("soft"),
        dynamic.list(soft_deps |> list.map(dynamic.string)),
      ),
    ])

  helpers.ValueTuple(
    "relations",
    accepted_types.CollectionType(collection_types.Dict(
      accepted_types.PrimitiveType(primitive_types.String),
      accepted_types.CollectionType(
        collection_types.List(accepted_types.PrimitiveType(
          primitive_types.String,
        )),
      ),
    )),
    relations_value,
  )
}
