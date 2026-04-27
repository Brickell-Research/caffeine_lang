import caffeine_lang/codegen/datadog_cql
import gleam/dict
import gleam/list
import gleeunit/should
import terra_madre/hcl

// ==== resolve_slo_to_hcl ====
// good_over_total
// * ✅ simple good over total query returns MetricSlo with query block
// time_slice
// * ✅ time_slice returns TimeSliceSlo with sli_specification block
// * ✅ time_slice with formula expression generates multiple metric_query blocks
pub fn resolve_slo_to_hcl_test() {
  // simple good over total query returns MetricSlo with query block
  {
    let assert Ok(datadog_cql.ResolvedSloHcl(slo_type, blocks)) =
      datadog_cql.resolve_slo_to_hcl(
        "numerator / denominator",
        dict.from_list([
          #("numerator", "sum:http.requests{status:2xx}"),
          #("denominator", "sum:http.requests{*}"),
        ]),
      )

    slo_type |> should.equal(datadog_cql.MetricSlo)
    blocks |> list.length |> should.equal(1)

    let assert [query_block] = blocks
    query_block.type_ |> should.equal("query")
    dict.get(query_block.attributes, "numerator")
    |> should.equal(Ok(hcl.StringLiteral("sum:http.requests{status:2xx}")))
    dict.get(query_block.attributes, "denominator")
    |> should.equal(Ok(hcl.StringLiteral("sum:http.requests{*}")))
  }

  // time_slice returns TimeSliceSlo with sli_specification block
  {
    let assert Ok(datadog_cql.ResolvedSloHcl(slo_type, blocks)) =
      datadog_cql.resolve_slo_to_hcl(
        "time_slice(avg:system.cpu{env:production} > 99.5 per 300s)",
        dict.new(),
      )

    slo_type |> should.equal(datadog_cql.TimeSliceSlo)
    blocks |> list.length |> should.equal(1)

    let assert [sli_spec_block] = blocks
    sli_spec_block.type_ |> should.equal("sli_specification")

    // Check nested time_slice block exists
    sli_spec_block.blocks |> list.length |> should.equal(1)
    let assert [time_slice_block] = sli_spec_block.blocks
    time_slice_block.type_ |> should.equal("time_slice")
    dict.get(time_slice_block.attributes, "comparator")
    |> should.equal(Ok(hcl.StringLiteral(">")))
    dict.get(time_slice_block.attributes, "query_interval_seconds")
    |> should.equal(Ok(hcl.IntLiteral(300)))
    dict.get(time_slice_block.attributes, "threshold")
    |> should.equal(Ok(hcl.FloatLiteral(99.5)))
  }

  // time_slice with formula expression generates multiple metric_query blocks
  {
    let assert Ok(datadog_cql.ResolvedSloHcl(slo_type, blocks)) =
      datadog_cql.resolve_slo_to_hcl(
        "time_slice((build_time + deploy_time) >= 600000 per 5m)",
        dict.from_list([
          #(
            "build_time",
            "sum:circleci.completed_build_time.avg{job_name:build-prod}",
          ),
          #(
            "deploy_time",
            "sum:circleci.completed_build_time.avg{job_name:deploy-prod}",
          ),
        ]),
      )

    slo_type |> should.equal(datadog_cql.TimeSliceSlo)
    blocks |> list.length |> should.equal(1)

    let assert [sli_spec_block] = blocks
    sli_spec_block.type_ |> should.equal("sli_specification")

    // Check nested time_slice block
    let assert [time_slice_block] = sli_spec_block.blocks
    time_slice_block.type_ |> should.equal("time_slice")
    dict.get(time_slice_block.attributes, "comparator")
    |> should.equal(Ok(hcl.StringLiteral(">=")))
    dict.get(time_slice_block.attributes, "threshold")
    |> should.equal(Ok(hcl.FloatLiteral(600_000.0)))

    // Check the outer query block contains formula + 2 inner query blocks
    let assert [outer_query_block] = time_slice_block.blocks
    outer_query_block.type_ |> should.equal("query")
    // Should have: 1 formula block + 2 query blocks (one per metric)
    outer_query_block.blocks |> list.length |> should.equal(3)

    // Find the formula block
    let formula_blocks =
      outer_query_block.blocks |> list.filter(fn(b) { b.type_ == "formula" })
    formula_blocks |> list.length |> should.equal(1)
    let assert [formula_block] = formula_blocks
    // Outer parentheses are stripped from the formula expression
    dict.get(formula_block.attributes, "formula_expression")
    |> should.equal(Ok(hcl.StringLiteral("build_time + deploy_time")))

    // Find the inner query blocks (each contains a metric_query)
    let inner_query_blocks =
      outer_query_block.blocks |> list.filter(fn(b) { b.type_ == "query" })
    inner_query_blocks |> list.length |> should.equal(2)

    // Extract metric_query blocks and verify their names
    let metric_names =
      inner_query_blocks
      |> list.flat_map(fn(qb) { qb.blocks })
      |> list.filter(fn(b) { b.type_ == "metric_query" })
      |> list.filter_map(fn(mq) {
        case dict.get(mq.attributes, "name") {
          Ok(hcl.StringLiteral(name)) -> Ok(name)
          _ -> Error(Nil)
        }
      })

    // Should have both build_time and deploy_time
    metric_names |> list.contains("build_time") |> should.be_true
    metric_names |> list.contains("deploy_time") |> should.be_true
  }
}
