import caffeine_lang/phase_1/parser/specification/basic_types_specification
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/common/accepted_types
import gleam/result
import gleamy_spec/extensions.{describe, it}
import gleamy_spec/gleeunit

pub fn parse_basic_types_specification_test() {
  describe("parse_basic_types_specification", fn() {
    it("should parse valid basic types", fn() {
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
          attribute_type: accepted_types.NonEmptyList(accepted_types.String),
        ),
      ]

      let actual =
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types.yaml",
        )

      actual
      |> gleeunit.equal(Ok(expected_basic_types))
    })

    it("should return an error when attribute_type is missing", fn() {
      let actual =
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_missing_attribute_type.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing attribute_type")
        Ok(_) -> panic as "Expected error"
      }
    })

    it("should return an error when attribute_name is missing", fn() {
      let actual =
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_missing_attribute_name.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal("Missing attribute_name")
        Ok(_) -> panic as "Expected error"
      }
    })

    it("should return an error for unrecognized attribute type", fn() {
      let actual =
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_unrecognized_attribute_type.yaml",
        )

      actual
      |> result.is_error()
      |> gleeunit.be_true()

      case actual {
        Error(msg) ->
          msg
          |> gleeunit.equal(
            "Unknown attribute type: LargeNumber. Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
          )
        Ok(_) -> panic as "Expected error"
      }
    })
  })
}
