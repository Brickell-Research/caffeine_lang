import caffeine_lang/errors
import caffeine_lang/linker/blueprints
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import test_helpers

// ==== validate_blueprints ====
// * ✅ happy path - empty list
// * ✅ happy path - single valid blueprint preserves params
// * ✅ happy path - multiple valid blueprints
// * ✅ happy path - blueprint with no inputs (partial inputs allowed)
// * ✅ happy path - empty params
// * ✅ duplicates - duplicate names rejected
// * ✅ input validation - extra input field rejected
// * ✅ input validation - wrong type input value rejected
pub fn validate_blueprints_test() {
  // Happy path - empty list
  [#("empty list", [], Ok([]))]
  |> test_helpers.table_test_1(fn(bps) { blueprints.validate_blueprints(bps) })

  // Happy path - single valid blueprint, params preserved
  [
    #(
      "single valid blueprint preserves params",
      [
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.from_list([
            #("percentile", types.PrimitiveType(types.NumericType(types.Float))),
            #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
            #("value", types.PrimitiveType(types.String)),
          ]),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ],
      Ok([
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.from_list([
            #("percentile", types.PrimitiveType(types.NumericType(types.Float))),
            #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
            #("value", types.PrimitiveType(types.String)),
          ]),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) { blueprints.validate_blueprints(bps) })

  // No inputs - allowed since blueprints can provide partial inputs
  [
    #(
      "blueprint with no inputs (partial inputs allowed)",
      [
        blueprints.Blueprint(
          name: "minimal",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - empty params
  [
    #(
      "empty params",
      [
        blueprints.Blueprint(
          name: "minimal_params",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - multiple blueprints
  [
    #(
      "multiple valid blueprints",
      [
        blueprints.Blueprint(
          name: "first",
          params: dict.new(),
          inputs: dict.new(),
        ),
        blueprints.Blueprint(
          name: "second",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps) {
      Ok(result) -> list.length(result) == 2
      Error(_) -> False
    }
  })

  // Duplicate names
  [
    #(
      "duplicate names rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.new(),
        ),
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "Duplicate blueprint names: success_rate",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) { blueprints.validate_blueprints(bps) })

  // Extra input field
  [
    #(
      "extra input field rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.from_list([
            #("value", types.PrimitiveType(types.String)),
          ]),
          inputs: dict.from_list([
            #("value", value.StringValue("foobar")),
            #("extra", value.StringValue("bad")),
          ]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: blueprint 'success_rate' - Extra keys in input: extra",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) { blueprints.validate_blueprints(bps) })

  // Wrong type input value
  [
    #(
      "wrong type input value rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          params: dict.from_list([
            #("value", types.PrimitiveType(types.String)),
          ]),
          inputs: dict.from_list([#("value", value.IntValue(123))]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: blueprint 'success_rate' - expected (String) received (Int) value (123) for (value)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) { blueprints.validate_blueprints(bps) })
}
