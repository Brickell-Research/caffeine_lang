import caffeine_lang/phase_1/parser/specification/basic_types_specification
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/common/accepted_types
import gleam/result
import gleeunit/should

pub fn parse_basic_types_specification_parses_valid_basic_types_test() {
        let expected_basic_types = [
          basic_type.BasicType(
            attribute_name: "team_name",
            attribute_type: accepted_types.String,
          ),
          basic_type.BasicType(
            attribute_name: "number_of_users",
            attribute_type: accepted_types.Integer,
          ),
          basic_type.BasicType(
            attribute_name: "accepted_status_codes",
            attribute_type: accepted_types.List(accepted_types.String),
          ),
        ]

  let actual =
    basic_types_specification.parse_basic_types_specification(
      "test/artifacts/specifications/basic_types.yaml",
    )
  
  actual
  |> should.equal(Ok(expected_basic_types))
}

pub fn parse_basic_types_specification_returns_error_when_attribute_type_is_missing_test() {
  let actual =
    basic_types_specification.parse_basic_types_specification(
      "test/artifacts/specifications/basic_types_missing_attribute_type.yaml",
    )
  
  actual
  |> result.is_error()
  |> should.be_true()
  
  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing attribute_type")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_basic_types_specification_returns_error_when_attribute_name_is_missing_test() {
  let actual =
    basic_types_specification.parse_basic_types_specification(
      "test/artifacts/specifications/basic_types_missing_attribute_name.yaml",
    )
  
  actual
  |> result.is_error()
  |> should.be_true()
  
  case actual {
    Error(msg) ->
      msg
      |> should.equal("Missing attribute_name")
    Ok(_) -> panic as "Expected error"
  }
}

pub fn parse_basic_types_specification_returns_error_for_unrecognized_attribute_type_test() {
  let actual =
    basic_types_specification.parse_basic_types_specification(
      "test/artifacts/specifications/basic_types_unrecognized_attribute_type.yaml",
    )
  
  actual
  |> result.is_error()
  |> should.be_true()
  
  case actual {
    Error(msg) ->
      msg
      |> should.equal("Unknown attribute type: LargeNumber")
    Ok(_) -> panic as "Expected error"
  }
}
