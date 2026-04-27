/// Datadog-specific CQL → Terraform HCL emission.
///
/// CQL itself (parser/printer/resolver) is vendor-neutral; this module is the
/// Datadog adapter that turns a parsed evaluation expression into the HCL
/// block tree consumed by the `datadog_service_level_objective` resource.
import caffeine_lang/errors
import caffeine_query_language/ast
import caffeine_query_language/generator as cql_generator
import caffeine_query_language/parser
import caffeine_query_language/printer
import caffeine_query_language/resolver
import gleam/dict
import gleam/list
import gleam/result
import terra_madre/hcl

/// Represents a single named query for TimeSlice formulas.
pub type NamedQuery {
  NamedQuery(name: String, query: String)
}

/// Represents a resolved SLO query, either GoodOverTotal or TimeSlice.
pub type ResolvedSloQuery {
  ResolvedGoodOverTotal(numerator: String, denominator: String)
  ResolvedTimeSlice(
    comparator: String,
    interval_seconds: Int,
    threshold: Float,
    /// The formula expression (e.g., "build_time + deploy_time")
    formula_expression: String,
    /// List of named indicators referenced by the formula
    indicators: List(NamedQuery),
  )
}

/// Represents the SLO type for Datadog terraform generation.
pub type SloType {
  MetricSlo
  TimeSliceSlo
}

/// Resolved SLO with HCL blocks ready for terraform generation.
pub type ResolvedSloHcl {
  ResolvedSloHcl(slo_type: SloType, blocks: List(hcl.Block))
}

/// Parse a value expression, resolve to primitive, substitute words,
/// and return the resolved SLO query type.
@internal
pub fn resolve_slo_query_typed(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> Result(ResolvedSloQuery, String) {
  case parser.parse_expr(value_expr) {
    Error(err) -> Error("Parse error: " <> err)
    Ok(exp) ->
      case resolver.resolve_primitives(exp) {
        Ok(resolver.GoodOverTotal(numerator_exp, denominator_exp)) -> {
          let numerator_str =
            cql_generator.substitute_words(numerator_exp, substitutions)
            |> printer.exp_to_string
          let denominator_str =
            cql_generator.substitute_words(denominator_exp, substitutions)
            |> printer.exp_to_string
          Ok(ResolvedGoodOverTotal(numerator_str, denominator_str))
        }
        Ok(resolver.TimeSlice(comparator, interval_seconds, threshold, query)) -> {
          let comparator_str = case comparator {
            ast.LessThan -> "<"
            ast.LessThanOrEqualTo -> "<="
            ast.GreaterThan -> ">"
            ast.GreaterThanOrEqualTo -> ">="
          }
          case parser.parse_expr(query) {
            Ok(query_exp) -> {
              let words = cql_generator.extract_words(query_exp)
              let named_queries =
                words
                |> list.filter_map(fn(word) {
                  case dict.get(substitutions, word) {
                    Ok(resolved) -> Ok(NamedQuery(word, resolved))
                    Error(_) -> Error(Nil)
                  }
                })
              case named_queries {
                [] ->
                  Ok(
                    ResolvedTimeSlice(
                      comparator_str,
                      interval_seconds,
                      threshold,
                      "query1",
                      [NamedQuery("query1", query)],
                    ),
                  )
                _ -> {
                  let formula_expr = printer.strip_outer_parens(query)
                  Ok(ResolvedTimeSlice(
                    comparator_str,
                    interval_seconds,
                    threshold,
                    formula_expr,
                    named_queries,
                  ))
                }
              }
            }
            Error(_) -> {
              let resolved_query =
                dict.get(substitutions, query) |> result.unwrap(query)
              Ok(
                ResolvedTimeSlice(
                  comparator_str,
                  interval_seconds,
                  threshold,
                  "query1",
                  [NamedQuery("query1", resolved_query)],
                ),
              )
            }
          }
        }
        Error(err) -> Error("Resolution error: " <> errors.to_message(err))
      }
  }
}

/// Parse a value expression, resolve to primitive, substitute words,
/// and return HCL blocks ready for Datadog terraform generation.
@internal
pub fn resolve_slo_to_hcl(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> Result(ResolvedSloHcl, String) {
  case resolve_slo_query_typed(value_expr, substitutions) {
    Ok(ResolvedGoodOverTotal(numerator, denominator)) -> {
      let query_block =
        hcl.simple_block("query", [
          #("numerator", hcl.StringLiteral(numerator)),
          #("denominator", hcl.StringLiteral(denominator)),
        ])
      Ok(ResolvedSloHcl(MetricSlo, [query_block]))
    }
    Ok(ResolvedTimeSlice(
      comparator,
      interval_seconds,
      threshold,
      formula_expression,
      named_queries,
    )) -> {
      let inner_query_blocks =
        named_queries
        |> list.map(fn(nq) {
          let metric_query_block =
            hcl.Block(
              type_: "metric_query",
              labels: [],
              attributes: dict.from_list([
                #("data_source", hcl.StringLiteral("metrics")),
                #("name", hcl.StringLiteral(nq.name)),
                #("query", hcl.StringLiteral(nq.query)),
              ]),
              blocks: [],
            )
          hcl.Block(type_: "query", labels: [], attributes: dict.new(), blocks: [
            metric_query_block,
          ])
        })

      let formula_block =
        hcl.Block(
          type_: "formula",
          labels: [],
          attributes: dict.from_list([
            #("formula_expression", hcl.StringLiteral(formula_expression)),
          ]),
          blocks: [],
        )

      let outer_query_block =
        hcl.Block(type_: "query", labels: [], attributes: dict.new(), blocks: [
          formula_block,
          ..inner_query_blocks
        ])

      let time_slice_block =
        hcl.Block(
          type_: "time_slice",
          labels: [],
          attributes: dict.from_list([
            #("comparator", hcl.StringLiteral(comparator)),
            #("query_interval_seconds", hcl.IntLiteral(interval_seconds)),
            #("threshold", hcl.FloatLiteral(threshold)),
          ]),
          blocks: [outer_query_block],
        )

      let sli_specification_block =
        hcl.Block(
          type_: "sli_specification",
          labels: [],
          attributes: dict.new(),
          blocks: [time_slice_block],
        )

      Ok(ResolvedSloHcl(TimeSliceSlo, [sli_specification_block]))
    }
    Error(err) -> Error(err)
  }
}
