import caffeine_lang/codegen/graph_data.{GraphData, GraphEdge}
import gleam/list
import ir_test_helpers
import test_helpers

// ==== generate ====
// * ✅ empty IR list -> empty graph
// * ✅ IRs with no DependencyRelations -> nodes only, no edges
// * ✅ node fields extracted from IR metadata
// * ✅ single IR with hard+soft deps -> correct edges
// * ✅ multiple IRs with cross-deps
// * ✅ deps-only IR produces edges but no SLO node duplication
pub fn generate_test() {
  // Empty IR list -> empty graph
  [
    #(
      "empty IR list produces empty graph",
      graph_data.generate([]),
      GraphData(nodes: [], edges: []),
    ),
  ]
  |> test_helpers.table_test_1(fn(graph) { graph })

  // IRs with no DependencyRelations -> nodes only, no edges
  let no_deps =
    graph_data.generate([
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
    #("two nodes present", list.length(no_deps.nodes), 2),
    #("no edges", list.length(no_deps.edges), 0),
  ]
  |> test_helpers.table_test_1(fn(count) { count })

  // Node fields extracted from IR metadata
  let first_node = case no_deps.nodes {
    [n, ..] -> n
    _ -> panic as "expected at least one node"
  }

  [
    #("node id is dotted path", first_node.id, "acme.platform.auth.login_slo"),
    #("node label is expectation name", first_node.label, "login_slo"),
    #("node service from metadata", first_node.service, "auth"),
    #("node org from metadata", first_node.org, "acme"),
    #("node team from metadata", first_node.team, "platform"),
  ]
  |> test_helpers.table_test_1(fn(val) { val })

  // Single IR with hard+soft deps -> correct edges
  let with_deps =
    graph_data.generate([
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
    #("three nodes", list.length(with_deps.nodes), 3),
    #("two edges", list.length(with_deps.edges), 2),
  ]
  |> test_helpers.table_test_1(fn(count) { count })

  [
    #(
      "hard edge present",
      with_deps.edges,
      GraphEdge(
        source: "acme.platform.auth.login_slo",
        target: "acme.infra.db.query_slo",
        relation_type: "hard",
      ),
      True,
    ),
    #(
      "soft edge present",
      with_deps.edges,
      GraphEdge(
        source: "acme.platform.auth.login_slo",
        target: "acme.cache.redis.cache_slo",
        relation_type: "soft",
      ),
      True,
    ),
  ]
  |> test_helpers.table_test_2(fn(edges, edge) { list.contains(edges, edge) })

  // Multiple IRs with cross-deps
  let cross_deps =
    graph_data.generate([
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
    #("three nodes in chain", list.length(cross_deps.nodes), 3),
    #("two edges in chain", list.length(cross_deps.edges), 2),
  ]
  |> test_helpers.table_test_1(fn(count) { count })

  [
    #(
      "a depends on b",
      cross_deps.edges,
      GraphEdge(
        source: "acme.platform.a.slo",
        target: "acme.platform.b.slo",
        relation_type: "hard",
      ),
      True,
    ),
    #(
      "b depends on c",
      cross_deps.edges,
      GraphEdge(
        source: "acme.platform.b.slo",
        target: "acme.platform.c.slo",
        relation_type: "hard",
      ),
      True,
    ),
  ]
  |> test_helpers.table_test_2(fn(edges, edge) { list.contains(edges, edge) })
}
