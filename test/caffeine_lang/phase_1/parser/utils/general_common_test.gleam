import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/types/common/accepted_types
import gleam/dict
import gleamy_spec/gleeunit

pub fn extract_params_from_file_path_extracts_team_and_service_names_from_valid_file_path_test() {
  let actual =
    general_common.extract_params_from_file_path(
      "test/caffeine_lang/artifacts/platform/reliable_service.yaml",
    )

  actual
  |> gleeunit.equal(
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
  |> gleeunit.equal(Error(
    "Invalid file path: expected at least 'team/service.yaml'",
  ))
}

pub fn string_to_accepted_type_converts_string_to_boolean_type_test() {
  // Simple types
  general_common.string_to_accepted_type("Boolean")
  |> gleeunit.equal(Ok(accepted_types.Boolean))

  general_common.string_to_accepted_type("Decimal")
  |> gleeunit.equal(Ok(accepted_types.Decimal))

  general_common.string_to_accepted_type("Integer")
  |> gleeunit.equal(Ok(accepted_types.Integer))

  general_common.string_to_accepted_type("String")
  |> gleeunit.equal(Ok(accepted_types.String))

  general_common.string_to_accepted_type("Unknown")
  |> gleeunit.equal(Error(
    "Unknown attribute type: Unknown. Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
  ))

  // Container types
  general_common.string_to_accepted_type("NonEmptyList(Boolean)")
  |> gleeunit.equal(Ok(accepted_types.NonEmptyList(accepted_types.Boolean)))

  general_common.string_to_accepted_type("NonEmptyList(Integer)")
  |> gleeunit.equal(Ok(accepted_types.NonEmptyList(accepted_types.Integer)))

  general_common.string_to_accepted_type("NonEmptyList(Decimal)")
  |> gleeunit.equal(Ok(accepted_types.NonEmptyList(accepted_types.Decimal)))

  general_common.string_to_accepted_type("NonEmptyList(String)")
  |> gleeunit.equal(Ok(accepted_types.NonEmptyList(accepted_types.String)))

  general_common.string_to_accepted_type("List(List(Boolean))")
  |> gleeunit.equal(Error(
    "Only one level of recursion is allowed for lists: List(List(Boolean))",
  ))

  general_common.string_to_accepted_type("NonEmptyList(Unknown)")
  |> gleeunit.equal(Error(
    "Unknown attribute type: NonEmptyList(Unknown). Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
  ))

  // Optional types
  general_common.string_to_accepted_type("Optional(Boolean)")
  |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Boolean)))

  general_common.string_to_accepted_type("Optional(Integer)")
  |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Integer)))

  general_common.string_to_accepted_type("Optional(Decimal)")
  |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Decimal)))

  general_common.string_to_accepted_type("Optional(String)")
  |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.String)))

  general_common.string_to_accepted_type("Optional(NonEmptyList(Boolean))")
  |> gleeunit.equal(
    Ok(
      accepted_types.Optional(accepted_types.NonEmptyList(
        accepted_types.Boolean,
      )),
    ),
  )

  general_common.string_to_accepted_type("Optional(NonEmptyList(Integer))")
  |> gleeunit.equal(
    Ok(
      accepted_types.Optional(accepted_types.NonEmptyList(
        accepted_types.Integer,
      )),
    ),
  )

  general_common.string_to_accepted_type("Optional(NonEmptyList(Decimal))")
  |> gleeunit.equal(
    Ok(
      accepted_types.Optional(accepted_types.NonEmptyList(
        accepted_types.Decimal,
      )),
    ),
  )

  general_common.string_to_accepted_type("Optional(NonEmptyList(String))")
  |> gleeunit.equal(
    Ok(
      accepted_types.Optional(accepted_types.NonEmptyList(accepted_types.String)),
    ),
  )

  general_common.string_to_accepted_type("Optional(List(List(Boolean)))")
  |> gleeunit.equal(Error(
    "Only one level of recursion is allowed for lists, even in optional: Optional(List(List(Boolean)))",
  ))

  general_common.string_to_accepted_type("Optional(NonEmptyList(Unknown))")
  |> gleeunit.equal(Error(
    "Unknown attribute type: Optional(NonEmptyList(Unknown)). Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
  ))
}
