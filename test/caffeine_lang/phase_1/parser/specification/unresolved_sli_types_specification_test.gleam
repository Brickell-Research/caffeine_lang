import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/types/unresolved/unresolved_sli_type
import gleam/dict
import gleam/result
import gleamy_spec/should

pub fn parse_unresolved_sli_types_specification_parses_valid_sli_types_test() {
  let expected_sli_types = [
    unresolved_sli_type.SliType(
      name: "latency",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: [
        "team_name",
        "accepted_status_codes",
      ],
    ),
    unresolved_sli_type.SliType(
      name: "error_rate",
      query_template_type: "good_over_bad",
      typed_instatiation_of_query_templates: dict.from_list([
        #("numerator_query", ""),
        #("denominator_query", ""),
      ]),
      specification_of_query_templatized_variables: ["number_of_users"],
    ),
  ]

  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/caffeine_lang/artifacts/specifications/sli_types.yaml",
    )

  actual
  |> should.equal(Ok(expected_sli_types))
}

pub fn parse_unresolved_sli_types_specification_returns_error_when_name_is_missing_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/caffeine_lang/artifacts/specifications/sli_types_missing_name.yaml",
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

pub fn parse_unresolved_sli_types_specification_returns_error_when_query_template_type_is_missing_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/caffeine_lang/artifacts/specifications/sli_types_missing_query_template.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing query_template_type")
    Ok(_) -> panic as "Expected error"
  }
}
