import caffeine_query_language/parser.{
  type Exp, type Operator, type Primary, PrimaryExp, PrimaryWord, Word,
}
import caffeine_query_language/resolver.{GoodOverTotal}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import terra_madre/hcl

/// Converts an expression AST node to its string representation.
pub fn exp_to_string(exp: Exp) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, None)
    parser.TimeSliceExpr(spec) ->
      "time_slice("
      <> spec.query
      <> " "
      <> comparator_to_string(spec.comparator)
      <> " "
      <> float_to_string(spec.threshold)
      <> " per "
      <> float_to_string(spec.interval_seconds)
      <> "s)"
    parser.OperatorExpr(numerator:, denominator:, operator:) -> {
      // Check if this entire expression tree is a path (all divisions with path-like components)
      case operator, is_path_expression(exp) {
        parser.Div, True -> {
          // This is a path, render without spaces
          exp_to_string_no_spaces(exp)
        }
        _, _ -> {
          // Normal expression with spaces
          let left = exp_to_string_with_context(numerator, Some(operator), True)
          let right =
            exp_to_string_with_context(denominator, Some(operator), False)
          let op = operator_to_datadog_query(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

fn comparator_to_string(comparator: parser.Comparator) -> String {
  case comparator {
    parser.LessThan -> "<"
    parser.LessThanOrEqualTo -> "<="
    parser.GreaterThan -> ">"
    parser.GreaterThanOrEqualTo -> ">="
  }
}

fn float_to_string(f: Float) -> String {
  // Check if it's a whole number (no fractional part)
  let truncated = float.truncate(f)
  let is_whole = int.to_float(truncated) == f
  case is_whole {
    True -> int.to_string(truncated)
    False -> float.to_string(f)
  }
}

// Check if an expression is a path (all divisions with simple word components)
// A path expression starts with a field name ending in colon (like http.url_details.path:)
fn is_path_expression(exp: Exp) -> Bool {
  // First check if the leftmost component is a field name (ends with :)
  case get_leftmost_word(exp) {
    Some(w) -> {
      case string.ends_with(w, ":") {
        True -> all_divisions(exp)
        False -> False
      }
    }
    None -> False
  }
}

// Get the leftmost word in an expression tree
fn get_leftmost_word(exp: Exp) -> Option(String) {
  case exp {
    parser.Primary(parser.PrimaryWord(parser.Word(w))) -> Some(w)
    parser.Primary(parser.PrimaryExp(inner_exp)) -> get_leftmost_word(inner_exp)
    parser.TimeSliceExpr(_) -> None
    parser.OperatorExpr(left, _, _) -> get_leftmost_word(left)
  }
}

// Check if an expression is all divisions (no other operators)
fn all_divisions(exp: Exp) -> Bool {
  case exp {
    parser.Primary(_) -> True
    parser.OperatorExpr(left, right, parser.Div) ->
      all_divisions(left) && all_divisions(right)
    _ -> False
  }
}

// Convert expression to string without spaces (for paths)
fn exp_to_string_no_spaces(exp: Exp) -> String {
  case exp {
    parser.Primary(parser.PrimaryWord(parser.Word(w))) -> w
    parser.OperatorExpr(left, right, parser.Div) ->
      exp_to_string_no_spaces(left) <> "/" <> exp_to_string_no_spaces(right)
    _ -> exp_to_string(exp)
  }
}

fn exp_to_string_with_context(
  exp: Exp,
  parent_op: Option(Operator),
  _is_left: Bool,
) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, parent_op)
    parser.TimeSliceExpr(_) -> exp_to_string(exp)
    parser.OperatorExpr(numerator:, denominator:, operator:) -> {
      // Check if this is a path expression to avoid adding spaces
      // This is important when the division is part of a larger expression (e.g., with AND)
      case operator, is_path_expression(exp) {
        parser.Div, True -> exp_to_string_no_spaces(exp)
        _, _ -> {
          // Not a path, render with spaces
          let left = exp_to_string_with_context(numerator, Some(operator), True)
          let right =
            exp_to_string_with_context(denominator, Some(operator), False)
          let op = operator_to_datadog_query(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

fn primary_to_string(primary: Primary, _parent_op: Option(Operator)) -> String {
  case primary {
    PrimaryWord(word:) -> word.value
    PrimaryExp(exp:) -> {
      // Always preserve explicit parentheses from the original input
      "(" <> exp_to_string(exp) <> ")"
    }
  }
}

@internal
pub fn operator_to_datadog_query(operator: parser.Operator) -> String {
  case operator {
    parser.Add -> "+"
    parser.Sub -> "-"
    parser.Mul -> "*"
    parser.Div -> "/"
  }
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
    parser.Primary(PrimaryWord(Word(name))) -> {
      let value = dict.get(substitutions, name) |> result.unwrap(name)
      parser.Primary(PrimaryWord(Word(value)))
    }
    parser.Primary(PrimaryExp(inner)) ->
      parser.Primary(PrimaryExp(substitute_words(inner, substitutions)))
    parser.TimeSliceExpr(spec) -> {
      // Substitute in the query string if it matches a key
      let query =
        dict.get(substitutions, spec.query) |> result.unwrap(spec.query)
      parser.TimeSliceExpr(parser.TimeSliceExp(..spec, query: query))
    }
    parser.OperatorExpr(left, right, op) ->
      parser.OperatorExpr(
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
    parser.Primary(PrimaryWord(Word(name))) -> [name]
    parser.Primary(PrimaryExp(inner)) -> extract_words(inner)
    parser.TimeSliceExpr(_) -> []
    parser.OperatorExpr(left, right, _) ->
      list.append(extract_words(left), extract_words(right))
      |> list.unique
  }
}

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
    /// List of named queries referenced by the formula
    queries: List(NamedQuery),
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
pub fn resolve_slo_query_typed(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> Result(ResolvedSloQuery, String) {
  case parser.parse_expr(value_expr) {
    Error(err) -> Error("Parse error: " <> err)
    Ok(exp_container) ->
      case resolver.resolve_primitives(exp_container) {
        Ok(GoodOverTotal(numerator_exp, denominator_exp)) -> {
          let numerator_str =
            substitute_words(numerator_exp, substitutions) |> exp_to_string
          let denominator_str =
            substitute_words(denominator_exp, substitutions) |> exp_to_string
          Ok(ResolvedGoodOverTotal(numerator_str, denominator_str))
        }
        Ok(resolver.TimeSlice(comparator, interval_seconds, threshold, query)) -> {
          let comparator_str = case comparator {
            resolver.LessThan -> "<"
            resolver.LessThanOrEqualTo -> "<="
            resolver.GreaterThan -> ">"
            resolver.GreaterThanOrEqualTo -> ">="
          }
          // Parse the query as an expression to extract word references
          // The query could be a single word like "query1" or a formula like "(a + b)"
          case parser.parse_expr(query) {
            Ok(query_exp_container) -> {
              let query_exp = query_exp_container.exp
              let words = extract_words(query_exp)
              // Build named queries by looking up each word in substitutions
              let named_queries =
                words
                |> list.filter_map(fn(word) {
                  case dict.get(substitutions, word) {
                    Ok(resolved) -> Ok(NamedQuery(word, resolved))
                    Error(_) -> Error(Nil)
                  }
                })
              // If no substitutions were found, the query is likely a literal metric query
              // In that case, use "query1" as the formula expression and the query as-is
              case named_queries {
                [] ->
                  Ok(ResolvedTimeSlice(
                    comparator_str,
                    interval_seconds,
                    threshold,
                    "query1",
                    [NamedQuery("query1", query)],
                  ))
                _ ->
                  // Use the original query string as the formula expression
                  Ok(ResolvedTimeSlice(
                    comparator_str,
                    interval_seconds,
                    threshold,
                    query,
                    named_queries,
                  ))
              }
            }
            Error(_) -> {
              // If parsing fails, treat as a single literal query (backwards compat)
              let resolved_query =
                dict.get(substitutions, query) |> result.unwrap(query)
              Ok(ResolvedTimeSlice(
                comparator_str,
                interval_seconds,
                threshold,
                "query1",
                [NamedQuery("query1", resolved_query)],
              ))
            }
          }
        }
        Error(err) -> Error("Resolution error: " <> err.msg)
      }
  }
}

/// Parse a value expression, resolve to GoodOverTotal primitive, substitute words,
/// and return the numerator and denominator as strings.
/// Panics if parsing or resolution fails.
pub fn resolve_slo_query(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> #(String, String) {
  case resolve_slo_query_typed(value_expr, substitutions) {
    Ok(ResolvedGoodOverTotal(numerator, denominator)) -> #(numerator, denominator)
    _ -> #("", "")
  }
}

/// Parse a value expression, resolve to primitive, substitute words,
/// and return HCL blocks ready for Datadog terraform generation.
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
      // Generate a metric_query block for each named query
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
          hcl.Block(
            type_: "query",
            labels: [],
            attributes: dict.new(),
            blocks: [metric_query_block],
          )
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
        hcl.Block(
          type_: "query",
          labels: [],
          attributes: dict.new(),
          blocks: [formula_block, ..inner_query_blocks],
        )

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
