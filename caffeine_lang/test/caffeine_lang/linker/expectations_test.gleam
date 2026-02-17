import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/linker/blueprints
import caffeine_lang/linker/expectations
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import test_helpers

// ==== Helpers ====
fn blueprints() -> List(blueprints.Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate",
      artifact_refs: [SLO],
      params: dict.from_list([
        #("percentile", types.PrimitiveType(types.NumericType(types.Float))),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

fn blueprints_with_inputs() -> List(blueprints.Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaults",
      artifact_refs: [SLO],
      params: dict.from_list([
        #("vendor", types.PrimitiveType(types.String)),
        #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
      ]),
      inputs: dict.from_list([
        #("vendor", value.StringValue(constants.vendor_datadog)),
      ]),
    ),
  ]
}

fn blueprints_with_defaulted() -> List(blueprints.Blueprint) {
  [
    blueprints.Blueprint(
      name: "success_rate_with_defaulted",
      artifact_refs: [SLO],
      params: dict.from_list([
        #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
        #(
          "default_env",
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.String),
            "production",
          )),
        ),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

const source_path = "org/team/service.caffeine"

// ==== validate_expectations ====
// * ✅ happy path - empty expectations list
// * ✅ happy path - single expectation paired with blueprint
// * ✅ happy path - multiple expectations
// * ✅ happy path - expectation with defaulted param (input omitted is fine)
// * ✅ duplicates - duplicate expectation names within file
// * ✅ invalid blueprint ref - blueprint_ref references non-existent blueprint
// * ✅ overshadowing - expectation inputs cannot overshadow blueprint inputs
// * ✅ input validation - missing required input
// * ✅ input validation - extra input field not in params
// * ✅ input validation - wrong type input value
pub fn validate_expectations_test() {
  // Happy path - empty list
  [#("empty expectations list", [], Ok([]))]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })

  // Happy path - single expectation paired with blueprint
  [
    #(
      "single expectation paired with blueprint",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([#("percentile", value.FloatValue(99.9))]),
        ),
      ],
      Ok([
        #(
          expectations.Expectation(
            name: "my_expectation",
            blueprint_ref: "success_rate",
            inputs: dict.from_list([#("percentile", value.FloatValue(99.9))]),
          ),
          blueprints.Blueprint(
            name: "success_rate",
            artifact_refs: [SLO],
            params: dict.from_list([
              #(
                "percentile",
                types.PrimitiveType(types.NumericType(types.Float)),
              ),
            ]),
            inputs: dict.from_list([]),
          ),
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })

  // Happy path - expectation with defaulted param, input omitted is fine
  [
    #(
      "expectation with defaulted param (input omitted is fine)",
      [
        expectations.Expectation(
          name: "my_expectation_with_defaulted",
          blueprint_ref: "success_rate_with_defaulted",
          inputs: dict.from_list([#("threshold", value.FloatValue(99.9))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(
        exps,
        blueprints_with_defaulted(),
        from: source_path,
      )
    {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - multiple expectations
  [
    #(
      "multiple expectations",
      [
        expectations.Expectation(
          name: "first_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([#("percentile", value.FloatValue(99.9))]),
        ),
        expectations.Expectation(
          name: "second_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([#("percentile", value.FloatValue(95.0))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(exps, blueprints(), from: source_path)
    {
      Ok(result) -> list.length(result) == 2
      Error(_) -> False
    }
  })

  // Duplicate names
  [
    #(
      "duplicate expectation names within file",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([#("percentile", value.FloatValue(99.9))]),
        ),
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([#("percentile", value.FloatValue(95.0))]),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "Duplicate expectation names: my_expectation",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })

  // Invalid blueprint ref - references non-existent blueprint
  [
    #(
      "blueprint_ref references non-existent blueprint",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "nonexistent_blueprint",
          inputs: dict.from_list([#("percentile", value.FloatValue(99.9))]),
        ),
      ],
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(exps, blueprints(), from: source_path)
    {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Overshadowing blueprint inputs
  [
    #(
      "expectation inputs cannot overshadow blueprint inputs",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate_with_defaults",
          inputs: dict.from_list([
            #("vendor", value.StringValue("honeycomb")),
            #("threshold", value.FloatValue(99.9)),
          ]),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "expectation 'org.team.service.my_expectation' - overshadowing inputs from blueprint: vendor",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(
      exps,
      blueprints_with_inputs(),
      from: source_path,
    )
  })

  // Missing required input
  [
    #(
      "missing required input",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: expectation 'org.team.service.my_expectation' - Missing keys in input: percentile",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })

  // Extra input field
  [
    #(
      "extra input field not in params",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([
            #("percentile", value.FloatValue(99.9)),
            #("extra", value.StringValue("bad")),
          ]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: expectation 'org.team.service.my_expectation' - Extra keys in input: extra",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })

  // Wrong type input value
  [
    #(
      "wrong type input value",
      [
        expectations.Expectation(
          name: "my_expectation",
          blueprint_ref: "success_rate",
          inputs: dict.from_list([
            #("percentile", value.StringValue("not a float")),
          ]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: expectation 'org.team.service.my_expectation' - expected (Float) received (String) value (\"not a float\") for (percentile)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, blueprints(), from: source_path)
  })
}
