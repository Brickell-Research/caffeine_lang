import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/types/unresolved/unresolved_service
import gleam/result
import gleeunit/should

pub fn parse_unresolved_services_specification_parses_valid_services_test() {
  let expected_services = [
    unresolved_service.Service(name: "reliable_service", sli_types: [
      "latency",
      "error_rate",
    ]),
    unresolved_service.Service(name: "unreliable_service", sli_types: [
      "error_rate",
    ]),
  ]

  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/caffeine_lang/artifacts/specifications/services.yaml",
    )

  actual
  |> should.equal(Ok(expected_services))
}

pub fn parse_unresolved_services_specification_returns_error_when_sli_types_is_missing_test() {
  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/caffeine_lang/artifacts/specifications/services_missing_sli_types.yaml",
    )

  actual
  |> result.is_error()
  |> should.be_true()

  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing sli_types")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_unresolved_services_specification_returns_error_when_name_is_missing_test() {
  let actual =
    unresolved_services_specification.parse_unresolved_services_specification(
      "test/caffeine_lang/artifacts/specifications/services_missing_name.yaml",
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
