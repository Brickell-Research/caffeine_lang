import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/types/common/accepted_types
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/dict

pub fn extract_params_from_file_path_test() {
  describe("extract_params_from_file_path", fn() {
    it("should extract team and service names from valid file path", fn() {
      general_common.extract_params_from_file_path(
        "test/caffeine_lang/artifacts/platform/reliable_service.yaml",
      )
      |> gleeunit.equal(
        Ok(
          dict.from_list([
            #("team_name", "platform"),
            #("service_name", "reliable_service"),
          ]),
        ),
      )
    })

    it("should return an error for invalid file path", fn() {
      general_common.extract_params_from_file_path("reliable_service.yaml")
      |> gleeunit.equal(Error(
        "Invalid file path: expected at least 'team/service.yaml'",
      ))
    })
  })
}

pub fn string_to_accepted_type_test() {
  describe("string_to_accepted_type", fn() {
    describe("simple types", fn() {
      it("should convert string to Boolean type", fn() {
        general_common.string_to_accepted_type("Boolean")
        |> gleeunit.equal(Ok(accepted_types.Boolean))
      })

      it("should convert string to Decimal type", fn() {
        general_common.string_to_accepted_type("Decimal")
        |> gleeunit.equal(Ok(accepted_types.Decimal))
      })

      it("should convert string to Integer type", fn() {
        general_common.string_to_accepted_type("Integer")
        |> gleeunit.equal(Ok(accepted_types.Integer))
      })

      it("should convert string to String type", fn() {
        general_common.string_to_accepted_type("String")
        |> gleeunit.equal(Ok(accepted_types.String))
      })

      it("should return an error for unknown type", fn() {
        general_common.string_to_accepted_type("Unknown")
        |> gleeunit.equal(Error(
          "Unknown attribute type: Unknown. Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
        ))
      })
    })

    describe("container types", fn() {
      it("should convert string to NonEmptyList(Boolean)", fn() {
        general_common.string_to_accepted_type("NonEmptyList(Boolean)")
        |> gleeunit.equal(
          Ok(accepted_types.NonEmptyList(accepted_types.Boolean)),
        )
      })

      it("should convert string to NonEmptyList(Integer)", fn() {
        general_common.string_to_accepted_type("NonEmptyList(Integer)")
        |> gleeunit.equal(
          Ok(accepted_types.NonEmptyList(accepted_types.Integer)),
        )
      })

      it("should convert string to NonEmptyList(Decimal)", fn() {
        general_common.string_to_accepted_type("NonEmptyList(Decimal)")
        |> gleeunit.equal(
          Ok(accepted_types.NonEmptyList(accepted_types.Decimal)),
        )
      })

      it("should convert string to NonEmptyList(String)", fn() {
        general_common.string_to_accepted_type("NonEmptyList(String)")
        |> gleeunit.equal(
          Ok(accepted_types.NonEmptyList(accepted_types.String)),
        )
      })

      it("should return an error for nested lists", fn() {
        general_common.string_to_accepted_type("List(List(Boolean))")
        |> gleeunit.equal(Error(
          "Only one level of recursion is allowed for lists: List(List(Boolean))",
        ))
      })

      it("should return an error for NonEmptyList with unknown type", fn() {
        general_common.string_to_accepted_type("NonEmptyList(Unknown)")
        |> gleeunit.equal(Error(
          "Unknown attribute type: NonEmptyList(Unknown). Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
        ))
      })
    })

    describe("optional types", fn() {
      it("should convert string to Optional(Boolean)", fn() {
        general_common.string_to_accepted_type("Optional(Boolean)")
        |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Boolean)))
      })

      it("should convert string to Optional(Integer)", fn() {
        general_common.string_to_accepted_type("Optional(Integer)")
        |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Integer)))
      })

      it("should convert string to Optional(Decimal)", fn() {
        general_common.string_to_accepted_type("Optional(Decimal)")
        |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.Decimal)))
      })

      it("should convert string to Optional(String)", fn() {
        general_common.string_to_accepted_type("Optional(String)")
        |> gleeunit.equal(Ok(accepted_types.Optional(accepted_types.String)))
      })

      it("should convert string to Optional(NonEmptyList(Boolean))", fn() {
        general_common.string_to_accepted_type(
          "Optional(NonEmptyList(Boolean))",
        )
        |> gleeunit.equal(
          Ok(
            accepted_types.Optional(accepted_types.NonEmptyList(
              accepted_types.Boolean,
            )),
          ),
        )
      })

      it("should convert string to Optional(NonEmptyList(Integer))", fn() {
        general_common.string_to_accepted_type(
          "Optional(NonEmptyList(Integer))",
        )
        |> gleeunit.equal(
          Ok(
            accepted_types.Optional(accepted_types.NonEmptyList(
              accepted_types.Integer,
            )),
          ),
        )
      })

      it("should convert string to Optional(NonEmptyList(Decimal))", fn() {
        general_common.string_to_accepted_type(
          "Optional(NonEmptyList(Decimal))",
        )
        |> gleeunit.equal(
          Ok(
            accepted_types.Optional(accepted_types.NonEmptyList(
              accepted_types.Decimal,
            )),
          ),
        )
      })

      it("should convert string to Optional(NonEmptyList(String))", fn() {
        general_common.string_to_accepted_type("Optional(NonEmptyList(String))")
        |> gleeunit.equal(
          Ok(
            accepted_types.Optional(accepted_types.NonEmptyList(
              accepted_types.String,
            )),
          ),
        )
      })

      it("should return an error for Optional with nested lists", fn() {
        general_common.string_to_accepted_type("Optional(List(List(Boolean)))")
        |> gleeunit.equal(Error(
          "Only one level of recursion is allowed for lists, even in optional: Optional(List(List(Boolean)))",
        ))
      })

      it("should return an error for Optional(NonEmptyList(Unknown))", fn() {
        general_common.string_to_accepted_type(
          "Optional(NonEmptyList(Unknown))",
        )
        |> gleeunit.equal(Error(
          "Unknown attribute type: Optional(NonEmptyList(Unknown)). Supported: String, Integer, Boolean, Decimal, NonEmptyList(String), NonEmptyList(Integer), NonEmptyList(Boolean), NonEmptyList(Decimal), Optional(String), Optional(Integer), Optional(Boolean), Optional(Decimal), Optional(NonEmptyList(String)), Optional(NonEmptyList(Integer)), Optional(NonEmptyList(Boolean)), Optional(NonEmptyList(Decimal))",
        ))
      })
    })
  })
}
