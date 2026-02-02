import caffeine_query_language/ast.{
  type Exp, OperatorExpr, Primary, PrimaryExp, PrimaryWord, TimeSliceExp, Word,
}
import caffeine_query_language/parser
import caffeine_query_language/printer
import caffeine_query_language/resolver
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
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

/// Transform an expression tree by substituting word values using a dictionary.
/// Words found in the dictionary are replaced with their corresponding values.
/// Words not found in the dictionary are left unchanged.
@internal
pub fn substitute_words(
  exp: Exp,
  substitutions: dict.Dict(String, String),
) -> Exp {
  case exp {
    Primary(PrimaryWord(Word(name))) -> {
      let value = dict.get(substitutions, name) |> result.unwrap(name)
      Primary(PrimaryWord(Word(value)))
    }
    Primary(PrimaryExp(inner)) ->
      Primary(PrimaryExp(substitute_words(inner, substitutions)))
    ast.TimeSliceExpr(spec) -> {
      let query =
        dict.get(substitutions, spec.query) |> result.unwrap(spec.query)
      ast.TimeSliceExpr(TimeSliceExp(..spec, query: query))
    }
    OperatorExpr(left, right, op) ->
      OperatorExpr(
        substitute_words(left, substitutions),
        substitute_words(right, substitutions),
        op,
      )
  }
}

/// Extracts all word names from an expression AST.
/// Returns a list of unique word strings found in the expression.
@internal
pub fn extract_words(exp: Exp) -> List(String) {
  case exp {
    Primary(PrimaryWord(Word(name))) -> [name]
    Primary(PrimaryExp(inner)) -> extract_words(inner)
    ast.TimeSliceExpr(_) -> []
    OperatorExpr(left, right, _) ->
      list.append(extract_words(left), extract_words(right))
      |> list.unique
  }
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
            substitute_words(numerator_exp, substitutions)
            |> printer.exp_to_string
          let denominator_str =
            substitute_words(denominator_exp, substitutions)
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
              let words = extract_words(query_exp)
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
        Error(err) -> Error("Resolution error: " <> err.msg)
      }
  }
}

/// Parse a value expression, resolve it, substitute indicator names,
/// and return the resulting expression as a plain string.
/// Handles identity expressions (single words, compositions) and good-over-total divisions.
/// Rejects time_slice expressions (not valid for expression-based resolution).
@internal
pub fn resolve_slo_to_expression(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> Result(String, String) {
  use parsed <- result.try(
    parser.parse_expr(value_expr)
    |> result.map_error(fn(err) { "Parse error: " <> err }),
  )
  let exp = case resolver.resolve_primitives(parsed) {
    Ok(resolver.GoodOverTotal(num, den)) -> Ok(OperatorExpr(num, den, ast.Div))
    Ok(resolver.TimeSlice(..)) ->
      Error(
        "time_slice expressions are not supported for expression resolution",
      )
    // Not a division or time_slice — treat as direct expression (identity/composition).
    Error(_) -> Ok(parsed)
  }
  use exp <- result.try(exp)
  use <- validate_words_exist(exp, substitutions)
  Ok(substitute_words(exp, substitutions) |> printer.exp_to_string)
}

/// Validate that all words in an expression exist in the substitutions dict.
/// Returns an error listing any missing indicator names.
fn validate_words_exist(
  exp: Exp,
  substitutions: dict.Dict(String, String),
  next: fn() -> Result(String, String),
) -> Result(String, String) {
  let missing =
    extract_words(exp)
    |> list.filter(fn(word) {
      case dict.get(substitutions, word) {
        Ok(_) -> False
        Error(_) -> True
      }
    })
  case missing {
    [] -> next()
    _ ->
      Error(
        "evaluation references undefined indicators: "
        <> string.join(missing, ", "),
      )
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
