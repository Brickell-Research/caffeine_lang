import caffeine_lang/phase_1/parser/specification/basic_types_specification
import caffeine_lang/phase_2/linker/basic_type
import caffeine_lang/types/accepted_types
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit

fn create_basic_type(
  attribute_name: String,
  attribute_type: accepted_types.AcceptedTypes,
) -> basic_type.BasicType {
  basic_type.BasicType(
    attribute_name: attribute_name,
    attribute_type: attribute_type,
  )
}

pub fn parse_basic_types_specification_test() {
  describe("parse_basic_types_specification", fn() {
    describe("valid basic types", fn() {
      it("should parse valid basic types", fn() {
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types.yaml",
        )
        |> gleeunit.equal(
          Ok([
            create_basic_type("team_name", accepted_types.String),
            create_basic_type("number_of_users", accepted_types.Integer),
            create_basic_type(
              "accepted_status_codes",
              accepted_types.NonEmptyList(accepted_types.String),
            ),
          ]),
        )
      })
    })

    describe("invalid basic types", fn() {
      it("should return an error when attribute_type is missing", fn() {
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_missing_attribute_type.yaml",
        )
        |> gleeunit.equal(Error("Missing attribute_type"))
      })

      it("should return an error when attribute_name is missing", fn() {
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_missing_attribute_name.yaml",
        )
        |> gleeunit.equal(Error("Missing attribute_name"))
      })

      it("should return an error for unrecognized attribute type", fn() {
        basic_types_specification.parse_basic_types_specification(
          "test/caffeine_lang/artifacts/specifications/basic_types_unrecognized_attribute_type.yaml",
        )
        |> gleeunit.equal(Error(
          "Unknown attribute type: LargeNumber. Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
        ))
      })
    })
  })
}
