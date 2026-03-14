import caffeine_lang/errors
import caffeine_lang/linker/artifacts.{type ParamInfo, ParamInfo}
import caffeine_lang/linker/measurements
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import test_helpers

// ==== Helpers ====
fn slo_params() -> dict.Dict(String, ParamInfo) {
  dict.from_list([
    #(
      "threshold",
      ParamInfo(
        type_: types.PrimitiveType(types.NumericType(types.Float)),
        description: "",
      ),
    ),
    #(
      "value",
      ParamInfo(type_: types.PrimitiveType(types.String), description: ""),
    ),
  ])
}

// ==== validate_measurements ====
// * ✅ happy path - empty list
// * ✅ happy path - single valid measurement merges SLO params
// * ✅ happy path - multiple valid measurements
// * ✅ happy path - measurement with no inputs (partial inputs allowed)
// * ✅ happy path - empty params
// * ✅ duplicates - duplicate names rejected
// * ✅ duplicates - cannot overshadow SLO params with measurement params
// * ✅ input validation - extra input field rejected
// * ✅ input validation - wrong type input value rejected
pub fn validate_measurements_test() {
  // Happy path - empty list
  [#("empty list", [], Ok([]))]
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })

  // Happy path - single valid measurement, SLO params get merged in
  [
    #(
      "single valid measurement merges SLO params",
      [
        measurements.Measurement(
          name: "success_rate",
          params: dict.from_list([
            #("percentile", types.PrimitiveType(types.NumericType(types.Float))),
          ]),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ],
      Ok([
        measurements.Measurement(
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
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })

  // No inputs - allowed since measurements can provide partial inputs
  [
    #(
      "measurement with no inputs (partial inputs allowed)",
      [
        measurements.Measurement(
          name: "minimal",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case measurements.validate_measurements(bps, slo_params()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - empty params (no measurement-specific params, only SLO params)
  [
    #(
      "empty params",
      [
        measurements.Measurement(
          name: "minimal_params",
          params: dict.new(),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case measurements.validate_measurements(bps, slo_params()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - multiple measurements
  [
    #(
      "multiple valid measurements",
      [
        measurements.Measurement(
          name: "first",
          params: dict.new(),
          inputs: dict.new(),
        ),
        measurements.Measurement(
          name: "second",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case measurements.validate_measurements(bps, slo_params()) {
      Ok(result) -> list.length(result) == 2
      Error(_) -> False
    }
  })

  // Duplicate names
  [
    #(
      "duplicate names rejected",
      [
        measurements.Measurement(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.new(),
        ),
        measurements.Measurement(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "Duplicate measurement names: success_rate",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })

  // Overshadowing SLO params
  [
    #(
      "cannot overshadow SLO params with measurement params",
      [
        measurements.Measurement(
          name: "success_rate",
          params: dict.from_list([
            #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          ]),
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "measurement 'success_rate' - overshadowing inherited_params from artifact: threshold",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })

  // Extra input field
  [
    #(
      "extra input field rejected",
      [
        measurements.Measurement(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.from_list([
            #("value", value.StringValue("foobar")),
            #("extra", value.StringValue("bad")),
          ]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: measurement 'success_rate' - Extra keys in input: extra",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })

  // Wrong type input value
  [
    #(
      "wrong type input value rejected",
      [
        measurements.Measurement(
          name: "success_rate",
          params: dict.new(),
          inputs: dict.from_list([#("value", value.IntValue(123))]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: measurement 'success_rate' - expected (String) received (Int) value (123) for (value)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    measurements.validate_measurements(bps, slo_params())
  })
}
