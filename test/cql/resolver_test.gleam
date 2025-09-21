import caffeine_lang/cql/parser.{Primary, PrimaryWord, Word, parse_expr}
import caffeine_lang/cql/resolver.{GoodOverTotal, resolve_primitives}

pub fn resolve_primitives_good_over_total_test() {
  let input = "A / B"

  let expected =
    Ok(GoodOverTotal(
      Primary(PrimaryWord(Word("A"))),
      Primary(PrimaryWord(Word("B"))),
    ))

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  assert actual == expected
}

pub fn resolve_primitives_invalid_test() {
  let input = "A + B"

  let expected = Error("Invalid expression")

  let assert Ok(parsed) = parse_expr(input)
  let actual = resolve_primitives(parsed)

  assert actual == expected
}
