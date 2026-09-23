import caffeine_query_language/ast.{
  type Exp, type Substituted, OperatorExpr, Primary, PrimaryExp, PrimaryWord,
  TimeSliceExp, Word,
}
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
