import gleam/result
import gleam/string

pub type Query {
  Query(exp: Exp)
}

pub type ExpContainer {
  ExpContainer(exp: Exp)
}

pub type Operator {
  Add
  Sub
  Mul
  Div
}

pub type Exp {
  OperatorExpr(numerator: Exp, denominator: Exp, operator: Operator)
  Primary(primary: Primary)
}

pub type Primary {
  PrimaryWord(word: Word)
  PrimaryExp(exp: Exp)
}

pub type Word {
  Word(value: String)
}

// ============================================================================
// DEBUGGING UTILITIES
// ============================================================================

/// Pretty print an expression tree for debugging.
/// Useful for visualizing the AST structure.
pub fn debug_exp(exp: Exp) -> String {
  case exp {
    OperatorExpr(left, right, op) -> {
      let op_str = case op {
        Add -> "+"
        Sub -> "-"
        Mul -> "*"
        Div -> "/"
      }
      "(" <> debug_exp(left) <> " " <> op_str <> " " <> debug_exp(right) <> ")"
    }
    Primary(PrimaryWord(Word(value))) -> value
    Primary(PrimaryExp(inner)) -> "(" <> debug_exp(inner) <> ")"
  }
}

// ============================================================================
// PARSER IMPLEMENTATION
// ============================================================================

/// Parse an expression string into an ExpContainer.
/// 
/// Examples:
/// - "A + B" -> Addition of A and B
/// - "(A + B) / C" -> Division with parenthesized addition
/// - "A * B + C / D - E" -> Mixed operators with precedence
pub fn parse_expr(input: String) -> Result(ExpContainer, String) {
  use exp <- result.try(do_parse_expr(input))
  Ok(ExpContainer(exp))
}

/// Core parsing logic. Handles two cases:
/// 1. Fully parenthesized expressions: (expr) -> unwrap and parse inner
/// 2. Non-parenthesized: try to split by operators in precedence order
/// 
/// Operator precedence (lowest to highest): +, -, *, /
/// We search for lowest precedence first to build correct AST structure.
pub fn do_parse_expr(input: String) -> Result(Exp, String) {
  let trimmed = string.trim(input)

  case is_fully_parenthesized(trimmed) {
    True -> {
      // Strip outer parens and recursively parse inner expression
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      use inner_exp <- result.try(do_parse_expr(inner))
      Ok(Primary(PrimaryExp(inner_exp)))
    }
    False -> {
      // Try operators in precedence order (lowest to highest)
      // This ensures correct AST structure: lower precedence at root
      let operators = [#("+", Add), #("-", Sub), #("*", Mul), #("/", Div)]
      try_operators(trimmed, operators)
    }
  }
}

/// Check if expression is fully wrapped in balanced parentheses.
/// 
/// Returns True only if:
/// 1. Starts with '(' and ends with ')'
/// 2. The opening '(' matches the closing ')' (not an inner pair)
/// 
/// Examples:
/// - "(A + B)" -> True
/// - "(A) + (B)" -> False (not fully wrapped)
/// - "((A + B))" -> True
fn is_fully_parenthesized(input: String) -> Bool {
  string.starts_with(input, "(")
  && string.ends_with(input, ")")
  && { string.length(input) >= 2 && is_balanced_parens(input, 1, 1) }
}

/// Try to split expression by operators in order.
/// 
/// Strategy:
/// 1. Try each operator in sequence (lowest precedence first)
/// 2. If operator found at top level, split and recursively parse both sides
/// 3. If no operator found, treat entire input as a word (leaf node)
/// 
/// This builds the AST with correct precedence structure.
fn try_operators(
  input: String,
  operators: List(#(String, Operator)),
) -> Result(Exp, String) {
  case operators {
    // Base case: no operators found, this is a leaf word
    [] -> {
      let word = Word(input)
      Ok(Primary(PrimaryWord(word)))
    }
    // Try current operator
    [#(op_str, op), ..rest] -> {
      case find_operator(input, op_str) {
        Ok(#(left, right)) -> {
          // Found operator! Split and recursively parse both sides
          use left_exp <- result.try(do_parse_expr(left))
          use right_exp <- result.try(do_parse_expr(right))
          Ok(OperatorExpr(left_exp, right_exp, op))
        }
        // Operator not found at top level, try next operator
        Error(_) -> try_operators(input, rest)
      }
    }
  }
}

/// Find the rightmost occurrence of operator at parenthesis level 0.
/// 
/// We search for rightmost to handle left-associativity correctly.
/// Example: "A + B + C" should parse as "(A + B) + C"
fn find_operator(
  input: String,
  operator: String,
) -> Result(#(String, String), String) {
  find_rightmost_operator_at_level(input, operator, 0, 0, -1)
}

/// Check if parentheses are balanced from position `pos` with initial `count`.
/// 
/// Args:
/// - input: The string to check
/// - pos: Starting position (0-indexed)
/// - count: Initial parenthesis depth (1 means we're inside one open paren)
/// 
/// Returns True only if:
/// 1. Count reaches exactly 0 at the end of the string
/// 2. Count never reaches 0 before the end (no premature closing)
/// 
/// This ensures that for "(A + B)", starting at pos=1 with count=1,
/// we verify the closing ')' is at the very end.
pub fn is_balanced_parens(input: String, pos: Int, count: Int) -> Bool {
  case pos >= string.length(input) {
    // Reached end: balanced only if count is exactly 0
    True -> count == 0
    False -> {
      let char = string.slice(input, pos, 1)
      let new_count = case char {
        "(" -> count + 1
        ")" -> count - 1
        _ -> count
      }
      // If count reaches 0 before the end, parens close too early
      case new_count == 0 && pos < string.length(input) - 1 {
        True -> False
        False -> is_balanced_parens(input, pos + 1, new_count)
      }
    }
  }
}

/// Find rightmost occurrence of operator at parenthesis level 0.
/// 
/// Args:
/// - input: Expression string to search
/// - operator: Operator string to find (e.g., "+", "-")
/// - start_pos: Current search position
/// - paren_level: Current parenthesis nesting depth
/// - rightmost_pos: Position of rightmost match found so far (-1 if none)
/// 
/// Algorithm:
/// 1. Scan left-to-right, tracking parenthesis depth
/// 2. Record position whenever we find operator at level 0
/// 3. Return rightmost match (for left-associativity)
/// 
/// Example: "A + B + C" finds the second '+' at level 0
fn find_rightmost_operator_at_level(
  input: String,
  operator: String,
  start_pos: Int,
  paren_level: Int,
  rightmost_pos: Int,
) -> Result(#(String, String), String) {
  case start_pos >= string.length(input) {
    // Reached end of string
    True ->
      case rightmost_pos {
        -1 -> Error("Operator not found")
        pos -> {
          // Split at the rightmost operator position
          let left = string.trim(string.slice(input, 0, pos))
          let right_start = pos + string.length(operator)
          let right_length = string.length(input) - right_start
          let right =
            string.trim(string.slice(input, right_start, right_length))
          Ok(#(left, right))
        }
      }
    False -> {
      // Update parenthesis level based on current character
      let char = string.slice(input, start_pos, 1)
      let new_paren_level = case char {
        "(" -> paren_level + 1
        ")" -> paren_level - 1
        _ -> paren_level
      }

      // Check if current position has target operator at level 0
      let is_target_operator =
        paren_level == 0
        && string.slice(input, start_pos, string.length(operator)) == operator

      // Update rightmost position if we found a match
      let new_rightmost_pos = case is_target_operator {
        True -> start_pos
        False -> rightmost_pos
      }

      // Continue scanning
      find_rightmost_operator_at_level(
        input,
        operator,
        start_pos + 1,
        new_paren_level,
        new_rightmost_pos,
      )
    }
  }
}
