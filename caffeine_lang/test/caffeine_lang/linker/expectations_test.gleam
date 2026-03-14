import caffeine_lang/errors
import caffeine_lang/linker/expectations
import caffeine_lang/linker/measurements
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option
import test_helpers

// ==== Helpers ====
fn measurements() -> List(
  measurements.Measurement(measurements.MeasurementValidated),
) {
  [
    measurements.Measurement(
      name: "success_rate",
      params: dict.from_list([
        #(
          "percentile",
          types.PrimitiveType(types.NumericType(types.Percentage)),
        ),
      ]),
      inputs: dict.from_list([]),
    ),
  ]
}

fn measurements_with_inputs() -> List(
  measurements.Measurement(measurements.MeasurementValidated),
) {
  [
    measurements.Measurement(
      name: "success_rate_with_defaults",
      params: dict.from_list([
        #("env", types.PrimitiveType(types.String)),
        #("threshold", types.PrimitiveType(types.NumericType(types.Percentage))),
      ]),
      inputs: dict.from_list([
        #("env", value.StringValue("production")),
      ]),
    ),
  ]
}

fn measurements_with_defaulted() -> List(
  measurements.Measurement(measurements.MeasurementValidated),
) {
  [
    measurements.Measurement(
      name: "success_rate_with_defaulted",
      params: dict.from_list([
        #("threshold", types.PrimitiveType(types.NumericType(types.Percentage))),
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
// * ✅ happy path - single expectation paired with measurement
// * ✅ happy path - multiple expectations
// * ✅ happy path - expectation with defaulted param (input omitted is fine)
// * ✅ duplicates - duplicate expectation names within file
// * ✅ invalid measurement ref - measurement_ref references non-existent measurement
// * ✅ overshadowing - expectation inputs cannot overshadow measurement inputs
// * ✅ input validation - missing required input
// * ✅ input validation - extra input field not in params
// * ✅ input validation - wrong type input value
pub fn validate_expectations_test() {
  // Happy path - empty list
  [#("empty expectations list", [], Ok([]))]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })

  // Happy path - single expectation paired with measurement
  [
    #(
      "single expectation paired with measurement",
      [
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(99.9))]),
        ),
      ],
      Ok([
        #(
          expectations.Expectation(
            name: "my_expectation",
            measurement_ref: option.Some("success_rate"),
            inputs: dict.from_list([
              #("percentile", value.PercentageValue(99.9)),
            ]),
          ),
          option.Some(measurements.Measurement(
            name: "success_rate",
            params: dict.from_list([
              #(
                "percentile",
                types.PrimitiveType(types.NumericType(types.Percentage)),
              ),
            ]),
            inputs: dict.from_list([]),
          )),
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })

  // Happy path - expectation with defaulted param, input omitted is fine
  [
    #(
      "expectation with defaulted param (input omitted is fine)",
      [
        expectations.Expectation(
          name: "my_expectation_with_defaulted",
          measurement_ref: option.Some("success_rate_with_defaulted"),
          inputs: dict.from_list([#("threshold", value.PercentageValue(99.9))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(
        exps,
        measurements_with_defaulted(),
        slo_params: stdlib_artifacts.slo_params(),
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
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(99.9))]),
        ),
        expectations.Expectation(
          name: "second_expectation",
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(95.0))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(
        exps,
        measurements(),
        slo_params: stdlib_artifacts.slo_params(),
        from: source_path,
      )
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
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(99.9))]),
        ),
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(95.0))]),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "Duplicate expectation names: my_expectation",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })

  // Invalid measurement ref - references non-existent measurement
  [
    #(
      "measurement_ref references non-existent measurement",
      [
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("nonexistent_measurement"),
          inputs: dict.from_list([#("percentile", value.PercentageValue(99.9))]),
        ),
      ],
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    case
      expectations.validate_expectations(
        exps,
        measurements(),
        slo_params: stdlib_artifacts.slo_params(),
        from: source_path,
      )
    {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Overshadowing measurement inputs
  [
    #(
      "expectation inputs cannot overshadow measurement inputs",
      [
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("success_rate_with_defaults"),
          inputs: dict.from_list([
            #("env", value.StringValue("staging")),
            #("threshold", value.PercentageValue(99.9)),
          ]),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "expectation 'org.team.service.my_expectation' - overshadowing inputs from measurement: env",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(
      exps,
      measurements_with_inputs(),
      slo_params: stdlib_artifacts.slo_params(),
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
          measurement_ref: option.Some("success_rate"),
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
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })

  // Extra input field
  [
    #(
      "extra input field not in params",
      [
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([
            #("percentile", value.PercentageValue(99.9)),
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
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })

  // Wrong type input value
  [
    #(
      "wrong type input value",
      [
        expectations.Expectation(
          name: "my_expectation",
          measurement_ref: option.Some("success_rate"),
          inputs: dict.from_list([
            #("percentile", value.StringValue("not a float")),
          ]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: expectation 'org.team.service.my_expectation' - expected (Percentage) received (String) value (\"not a float\") for (percentile)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(exps) {
    expectations.validate_expectations(exps, measurements(), slo_params: stdlib_artifacts.slo_params(), from: source_path)
  })
}
