import caffeine_lang/codegen/dependency_graph
import gleam/string
import ir_test_helpers
import test_helpers

// ==== generate ====
// * ✅ empty IR list -> graph header only
// * ✅ IRs with no DependencyRelations -> nodes in subgraphs, no edges
// * ✅ nodes grouped by service into subgraphs
// * ✅ node labels are just the expectation name
// * ✅ single IR with hard+soft deps -> correct arrows
// * ✅ multiple IRs with cross-deps
pub fn generate_test() {
  // Empty IR list -> graph header only
  [
    #("empty IR list produces graph header only", [], "graph TD"),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_graph.generate(irs)
  })

  // IRs with no DependencyRelations -> nodes in subgraphs, no edges
  let no_deps_output =
    dependency_graph.generate([
      ir_test_helpers.make_slo_ir(
        "acme",
        "platform",
        "auth",
        "login_slo",
        threshold: 99.9,
      ),
      ir_test_helpers.make_slo_ir(
        "acme",
        "infra",
        "db",
        "query_slo",
        threshold: 99.99,
      ),
    ])

  [
    #("contains graph header", no_deps_output, "graph TD", True),
    #(
      "contains auth login node",
      no_deps_output,
      "acme_platform_auth_login_slo",
      True,
    ),
    #("contains db query node", no_deps_output, "acme_infra_db_query_slo", True),
    // Subgraph labels (grouped by service name)
    #("contains subgraph keyword", no_deps_output, "subgraph", True),
    #("contains auth subgraph label", no_deps_output, "\"auth\"", True),
    #("contains db subgraph label", no_deps_output, "\"db\"", True),
    #("contains end keyword", no_deps_output, "end", True),
    // Node labels are just the name
    #("contains login_slo node label", no_deps_output, "\"login_slo\"", True),
    #("contains query_slo node label", no_deps_output, "\"query_slo\"", True),
    // No edges
    #("no hard edges", no_deps_output, "-->", False),
    #("no soft edges", no_deps_output, "-.->", False),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })

  // Single IR with hard+soft deps -> correct arrows
  let with_deps_output =
    dependency_graph.generate([
      ir_test_helpers.make_ir_with_deps(
        "acme",
        "platform",
        "auth",
        "login_slo",
        hard_deps: ["acme.infra.db.query_slo"],
        soft_deps: ["acme.cache.redis.cache_slo"],
        threshold: 99.9,
      ),
      ir_test_helpers.make_slo_ir(
        "acme",
        "infra",
        "db",
        "query_slo",
        threshold: 99.99,
      ),
      ir_test_helpers.make_slo_ir(
        "acme",
        "cache",
        "redis",
        "cache_slo",
        threshold: 99.5,
      ),
    ])

  [
    #(
      "hard dependency arrow present",
      with_deps_output,
      "acme_platform_auth_login_slo -->|hard| acme_infra_db_query_slo",
      True,
    ),
    #(
      "soft dependency arrow present",
      with_deps_output,
      "acme_platform_auth_login_slo -.->|soft| acme_cache_redis_cache_slo",
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })

  // Multiple IRs with cross-deps grouped into subgraphs by service
  let cross_deps_output =
    dependency_graph.generate([
      ir_test_helpers.make_ir_with_deps(
        "acme",
        "platform",
        "a",
        "slo",
        hard_deps: ["acme.platform.b.slo"],
        soft_deps: [],
        threshold: 99.9,
      ),
      ir_test_helpers.make_ir_with_deps(
        "acme",
        "platform",
        "b",
        "slo",
        hard_deps: ["acme.platform.c.slo"],
        soft_deps: [],
        threshold: 99.99,
      ),
      ir_test_helpers.make_slo_ir(
        "acme",
        "platform",
        "c",
        "slo",
        threshold: 99.999,
      ),
    ])

  [
    #(
      "a depends on b",
      cross_deps_output,
      "acme_platform_a_slo -->|hard| acme_platform_b_slo",
      True,
    ),
    #(
      "b depends on c",
      cross_deps_output,
      "acme_platform_b_slo -->|hard| acme_platform_c_slo",
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_2(fn(output, substr) {
    string.contains(output, substr)
  })
}
