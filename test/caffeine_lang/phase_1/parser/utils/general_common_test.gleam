import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/types/common/accepted_types
import gleam/dict
import gleeunit/should

pub fn extract_params_from_file_path_extracts_team_and_service_names_from_valid_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path(
      "test/artifacts/platform/reliable_service.yaml",
    )

  actual
  |> should.equal(
    Ok(
      dict.from_list([
        #("team_name", "platform"),
        #("service_name", "reliable_service"),
      ]),
    ),
  )
}

pub fn extract_params_from_file_path_returns_error_for_invalid_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path("reliable_service.yaml")

  actual
  |> should.equal(Error(
    "Invalid file path: expected at least 'team/service.yaml'",
  ))
}

pub fn string_to_accepted_type_converts_string_to_boolean_type_test() {
  // Simple types
  general_common.string_to_accepted_type("Boolean")
  |> should.equal(Ok(accepted_types.Boolean))

  general_common.string_to_accepted_type("Decimal")
  |> should.equal(Ok(accepted_types.Decimal))

  general_common.string_to_accepted_type("Integer")
  |> should.equal(Ok(accepted_types.Integer))

  general_common.string_to_accepted_type("String")
  |> should.equal(Ok(accepted_types.String))

  general_common.string_to_accepted_type("Unknown")
  |> should.equal(Error(
    "Unknown attribute type: Unknown. Supported: String, Integer, Boolean, Decimal, List(String), List(Integer), List(Boolean), List(Decimal)",
  ))

  // Container types
  general_common.string_to_accepted_type("List(Boolean)")
  |> should.equal(Ok(accepted_types.List(accepted_types.Boolean)))

  general_common.string_to_accepted_type("List(Integer)")
  |> should.equal(Ok(accepted_types.List(accepted_types.Integer)))

  general_common.string_to_accepted_type("List(Decimal)")
  |> should.equal(Ok(accepted_types.List(accepted_types.Decimal)))

  general_common.string_to_accepted_type("List(String)")
  |> should.equal(Ok(accepted_types.List(accepted_types.String)))

  general_common.string_to_accepted_type("List(List(Boolean))")
  |> should.equal(Error(
    "Only one level of recursion is allowed for lists: List(List(Boolean))",
  ))

  general_common.string_to_accepted_type("List(Unknown)")
  |> should.equal(Error(
    "Unknown attribute type: List(Unknown). Supported: String, Integer, Boolean, Decimal, List(String), List(Integer), List(Boolean), List(Decimal)",
  ))
}
