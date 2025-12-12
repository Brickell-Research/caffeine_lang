import caffeine_query_language/parser.{
  type Exp, type Operator, type Primary, PrimaryExp, PrimaryWord, Word,
}
import caffeine_query_language/resolver.{
  type Primitives, GoodOverTotal, TimeSlice,
}
import gleam/dict
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Generates a Datadog query block from a resolved primitive.
/// Formats the numerator and denominator as a Datadog SLO query structure.
@internal
pub fn generate_datadog_query(primitive: Primitives) -> String {
  case primitive {
    GoodOverTotal(numerator, denominator) -> {
      "query {\n"
      <> "    numerator = \""
      <> numerator_exp_to_datadog_query(numerator)
      <> "\"\n"
      <> "    denominator = \""
      <> denominator_exp_to_datadog_query(denominator)
      <> "\"\n"
      <> "  }\n"
    }
    TimeSlice(comparator, interval_in_seconds, threshold, query) -> {
      "  sli_specification {
    time_slice {
      comparator               = " <> resolver.comparator_to_string(comparator) <> "
      query_interval_seconds   = " <> int.to_string(interval_in_seconds) <> "
      threshold                = " <> float_to_string(threshold) <> "
      query {
        formula {
          formula_expression = \"query1\"
        }
        query {
          metric_query {
            data_source = \"metrics\"
            name        = \"query1\"
            query       = \"" <> query <> "\"
          }
        }
      }
    }
  }"
    }
  }
}

fn numerator_exp_to_datadog_query(exp: Exp) -> String {
  // Unwrap outer PrimaryExp at top level only
  case exp {
    parser.Primary(PrimaryExp(exp:)) -> exp_to_string(exp)
    _ -> exp_to_string(exp)
  }
}

fn denominator_exp_to_datadog_query(exp: Exp) -> String {
  // Unwrap outer PrimaryExp at top level only
  case exp {
    parser.Primary(PrimaryExp(exp:)) -> exp_to_string(exp)
    _ -> exp_to_string(exp)
  }
}

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

/// Parse a value expression, resolve to GoodOverTotal primitive, substitute words,
/// and return the numerator and denominator as strings.
/// Panics if parsing or resolution fails.
pub fn resolve_slo_query(
  value_expr: String,
  substitutions: dict.Dict(String, String),
) -> #(String, String) {
  let assert Ok(exp_container) = parser.parse_expr(value_expr)
  case resolver.resolve_primitives(exp_container) {
    Ok(GoodOverTotal(numerator_exp, denominator_exp)) -> {
      let numerator_str =
        substitute_words(numerator_exp, substitutions) |> exp_to_string
      let denominator_str =
        substitute_words(denominator_exp, substitutions) |> exp_to_string
      #(numerator_str, denominator_str)
    }

    // TODO: handle error and handle time slice
    _ -> #("", "")
  }
}
