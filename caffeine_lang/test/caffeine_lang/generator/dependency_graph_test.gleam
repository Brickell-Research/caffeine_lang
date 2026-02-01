import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/helpers
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/generator/dependency_graph
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import gleam/string
import test_helpers

fn make_slo_ir(
  org: String,
  team: String,
  service: String,
  name: String,
  threshold: Float,
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

fn make_ir_with_deps(
  org: String,
  team: String,
  service: String,
  name: String,
  threshold: Float,
  hard_deps: List(String),
  soft_deps: List(String),
) -> semantic_analyzer.IntermediateRepresentation {
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
      ),
    ],
    vendor: option.Some(vendor.Datadog),
  )
}

// ==== generate ====
// * ✅ empty IR list -> graph header only
// * ✅ IRs with no DependencyRelations -> nodes only, no edges
// * ✅ single IR with hard+soft deps -> correct arrows
// * ✅ node labels include threshold
// * ✅ multiple IRs with cross-deps
pub fn generate_test() {
  // Empty IR list -> graph header only
  [
    #([], "graph LR"),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_graph.generate(irs)
  })

  // IRs with no DependencyRelations -> nodes only, no edges
  let no_deps_output =
    dependency_graph.generate([
      make_slo_ir("acme", "platform", "auth", "login_slo", 99.9),
      make_slo_ir("acme", "infra", "db", "query_slo", 99.99),
    ])

  [
    #(no_deps_output, "graph LR", True),
    #(no_deps_output, "acme_platform_auth_login_slo", True),
    #(no_deps_output, "acme_infra_db_query_slo", True),
    #(no_deps_output, "-->", False),
    #(no_deps_output, "-.->", False),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })

  // Single IR with hard+soft deps -> correct arrows
  let with_deps_output =
    dependency_graph.generate([
      make_ir_with_deps(
        "acme",
        "platform",
        "auth",
        "login_slo",
        99.9,
        ["acme.infra.db.query_slo"],
        ["acme.cache.redis.cache_slo"],
      ),
      make_slo_ir("acme", "infra", "db", "query_slo", 99.99),
      make_slo_ir("acme", "cache", "redis", "cache_slo", 99.5),
    ])

  [
    #(
      with_deps_output,
      "acme_platform_auth_login_slo -->|hard| acme_infra_db_query_slo",
      True,
    ),
    #(
      with_deps_output,
      "acme_platform_auth_login_slo -.->|soft| acme_cache_redis_cache_slo",
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })

  // Node labels include threshold
  [
    #(with_deps_output, "threshold: 99.9", True),
    #(with_deps_output, "threshold: 99.99", True),
    #(with_deps_output, "threshold: 99.5", True),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })

  // Multiple IRs with cross-deps
  let cross_deps_output =
    dependency_graph.generate([
      make_ir_with_deps(
        "acme",
        "platform",
        "a",
        "slo",
        99.9,
        ["acme.platform.b.slo"],
        [],
      ),
      make_ir_with_deps(
        "acme",
        "platform",
        "b",
        "slo",
        99.99,
        ["acme.platform.c.slo"],
        [],
      ),
      make_slo_ir("acme", "platform", "c", "slo", 99.999),
    ])

  [
    #(
      cross_deps_output,
      "acme_platform_a_slo -->|hard| acme_platform_b_slo",
      True,
    ),
    #(
      cross_deps_output,
      "acme_platform_b_slo -->|hard| acme_platform_c_slo",
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })
}
