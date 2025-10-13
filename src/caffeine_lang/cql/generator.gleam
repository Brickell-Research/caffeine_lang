import caffeine_lang/cql/parser.{
  type Exp, type Operator, type Primary, Add, Div, Mul, PrimaryExp, PrimaryWord,
  Sub,
}
import caffeine_lang/cql/resolver.{type Primitives, GoodOverTotal}
import gleam/option.{type Option, None, Some}
import gleam/string

// Datadog
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

pub fn exp_to_string(exp: Exp) -> String {
  case exp {
    parser.Primary(primary:) -> primary_to_string(primary, None)
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
          let right = exp_to_string_with_context(denominator, Some(operator), False)
          let op = operator_to_datadog_query(operator)
          left <> " " <> op <> " " <> right
        }
      }
    }
  }
}

// Check if an expression is a path (all divisions with simple word components)
// Excludes the leftmost component if it ends with colon (field name)
fn is_path_expression(exp: Exp) -> Bool {
  is_path_expression_helper(exp, True)
}

fn is_path_expression_helper(exp: Exp, is_leftmost: Bool) -> Bool {
  case exp {
    parser.Primary(parser.PrimaryWord(parser.Word(w))) -> {
      case is_leftmost && string.ends_with(w, ":") {
        True -> True  // Field names ending with : are allowed on the left
        False -> is_path_component(w)  // Other components must be path segments
      }
    }
    parser.OperatorExpr(left, right, parser.Div) -> 
      is_path_expression_helper(left, is_leftmost) && is_path_expression_helper(right, False)
    _ -> False
  }
}

// Check if a word is a path component (no underscores, simple alphanumeric)
fn is_path_component(s: String) -> Bool {
  // Path components don't have:
  // - underscores (metric names like metric_a have these)
  // - spaces
  // - both { and } (complete metric queries like metric{a:b} have these)
  // 
  // Path components CAN have:
  // - dots (field names like http.url_details.path)
  // - colons (field names end with :)
  // - wildcards (*)
  
  let has_complete_braces = string.contains(s, "{") && string.contains(s, "}")
  
  !string.contains(s, "_") && !string.contains(s, " ") && !has_complete_braces
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
    parser.OperatorExpr(numerator:, denominator:, operator:) -> {
      // Check if this is a path expression to avoid adding spaces
      case operator, is_path_expression(exp) {
        parser.Div, True -> exp_to_string_no_spaces(exp)
        _, _ ->
          exp_to_string_with_context(numerator, Some(operator), True)
          <> " "
          <> operator_to_datadog_query(operator)
          <> " "
          <> exp_to_string_with_context(denominator, Some(operator), False)
      }
    }
  }
}

fn primary_to_string(primary: Primary, parent_op: Option(Operator)) -> String {
  case primary {
    PrimaryWord(word:) -> word.value
    PrimaryExp(exp:) -> {
      // Check if parentheses are needed
      let needs_parens = case exp, parent_op {
        // If there's no parent operator, we don't need parens
        _, None -> False
        // If the inner expression is just a primary, check if it needs parens
        parser.Primary(_), _ -> False
        // If inner is an operator expression, check precedence
        parser.OperatorExpr(operator: inner_op, ..), Some(parent) ->
          needs_parentheses(inner_op, parent)
      }
      case needs_parens {
        True -> "(" <> exp_to_string(exp) <> ")"
        False -> exp_to_string(exp)
      }
    }
  }
}

fn needs_parentheses(inner_op: Operator, parent_op: Operator) -> Bool {
  let inner_prec = operator_precedence(inner_op)
  let parent_prec = operator_precedence(parent_op)
  inner_prec < parent_prec
}

fn operator_precedence(op: Operator) -> Int {
  case op {
    Add | Sub -> 1
    Mul | Div -> 2
  }
}

pub fn operator_to_datadog_query(operator: parser.Operator) -> String {
  case operator {
    parser.Add -> "+"
    parser.Sub -> "-"
    parser.Mul -> "*"
    parser.Div -> "/"
  }
}
