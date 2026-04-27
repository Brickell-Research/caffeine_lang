import caffeine_query_language/ast.{
  type Exp, type Substituted, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  TimeSliceExp, Word,
}
import caffeine_query_language/parser
import caffeine_query_language/printer
import caffeine_query_language/resolver
import gleam/dict
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// Transform an expression tree by substituting word values using a dictionary.
/// Words found in the dictionary are replaced with their corresponding values.
/// Words not found in the dictionary are left unchanged.
@internal
pub fn substitute_words(
  exp: Exp(a),
  substitutions: dict.Dict(String, String),
) -> Exp(Substituted) {
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
pub fn extract_words(exp: Exp(a)) -> List(String) {
  extract_words_loop(exp, set.new())
  |> set.to_list
  |> list.sort(string.compare)
}

/// Accumulates unique word names into a Set.
fn extract_words_loop(exp: Exp(a), acc: Set(String)) -> Set(String) {
  case exp {
    Primary(PrimaryWord(Word(name))) -> set.insert(acc, name)
    Primary(PrimaryExp(inner)) -> extract_words_loop(inner, acc)
    ast.TimeSliceExpr(_) -> acc
    OperatorExpr(left, right, _) ->
      extract_words_loop(right, extract_words_loop(left, acc))
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
  exp: Exp(a),
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
