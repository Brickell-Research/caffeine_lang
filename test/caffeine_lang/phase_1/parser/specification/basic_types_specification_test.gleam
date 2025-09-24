import caffeine_lang/phase_1/parser/specification/basic_types_specification
import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/common/accepted_types
import startest.{describe, it}
import startest/expect

pub fn basic_types_specification_tests() {
  describe("Basic Types Specification Parser", [
    describe("parse_basic_types_specification", [
      it("parses valid basic types", fn() {
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
        expect.to_equal(actual, Ok(expected_basic_types))
      }),
      it("returns error when attribute_type is missing", fn() {
        let actual =
          basic_types_specification.parse_basic_types_specification(
            "test/artifacts/specifications/basic_types_missing_attribute_type.yaml",
          )
        expect.to_equal(actual, Error("Missing attribute_type"))
      }),
      it("returns error when attribute_name is missing", fn() {
        let actual =
          basic_types_specification.parse_basic_types_specification(
            "test/artifacts/specifications/basic_types_missing_attribute_name.yaml",
          )
        expect.to_equal(actual, Error("Missing attribute_name"))
      }),
      it("returns error for unrecognized attribute type", fn() {
        let actual =
          basic_types_specification.parse_basic_types_specification(
            "test/artifacts/specifications/basic_types_unrecognized_attribute_type.yaml",
          )
        expect.to_equal(actual, Error("Unknown attribute type: LargeNumber"))
      }),
    ]),
  ])
}
