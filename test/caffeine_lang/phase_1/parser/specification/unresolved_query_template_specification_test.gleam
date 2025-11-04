import caffeine_lang/cql/parser.{
  Div, ExpContainer, OperatorExpr, Primary, PrimaryWord, Word,
}
import caffeine_lang/phase_1/parser/specification/unresolved_query_template_specification
import caffeine_lang/types/unresolved/unresolved_query_template_type
import gleam/result
import gleeunit/should

pub fn parse_unresolved_query_template_types_specification_parses_valid_query_template_types_test() {
  let expected_query_template_types = [
    unresolved_query_template_type.QueryTemplateType(
      name: "good_over_bad",
      specification_of_query_templates: [
        "team_name",
        "accepted_status_codes",
      ],
      query: ExpContainer(OperatorExpr(
        Primary(PrimaryWord(Word("numerator"))),
        Primary(PrimaryWord(Word("denominator"))),
        Div,
      )),
    ),
  ]

  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/caffeine_lang/artifacts/specifications/query_template_types.yaml",
    )

  actual
  |> should.equal(Ok(expected_query_template_types))
}

pub fn parse_unresolved_query_template_types_specification_returns_error_when_specification_of_query_templates_is_missing_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/caffeine_lang/artifacts/specifications/query_template_types_missing_specification_of_query_templates.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing specification_of_query_templates")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_query_template_types_specification_returns_error_when_name_is_missing_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/caffeine_lang/artifacts/specifications/query_template_types_missing_name.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing name")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_query_template_types_specification_returns_error_when_query_is_empty_test() {
  let actual =
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      "test/caffeine_lang/artifacts/specifications/query_template_types_missing_query.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Empty query string is not allowed")
    Ok(_) -> panic as "Expected error"
  }
}
