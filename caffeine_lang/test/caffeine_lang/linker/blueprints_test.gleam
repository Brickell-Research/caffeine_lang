import caffeine_lang/errors
import caffeine_lang/linker/artifacts.{
  type Artifact, ParamInfo, SLO,
}
import caffeine_lang/linker/blueprints
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import test_helpers

// ==== Helpers ====
fn artifacts() -> List(Artifact) {
  [
    artifacts.Artifact(
      type_: artifacts.SLO,
      description: "",
      params: dict.from_list([
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
      ]),
    ),
  ]
}

// ==== validate_blueprints ====
// * ✅ happy path - empty list
// * ✅ happy path - single valid blueprint merges artifact params
// * ✅ happy path - multiple valid blueprints
// * ✅ happy path - blueprint with no inputs (partial inputs allowed)
// * ✅ happy path - empty params
// * ✅ duplicates - duplicate names rejected
// * ✅ duplicates - cannot overshadow artifact params with blueprint params
// * ✅ duplicates - duplicate artifact refs rejected
// * ✅ empty - artifact_refs is empty list
// * ✅ input validation - extra input field rejected
// * ✅ input validation - wrong type input value rejected
pub fn validate_blueprints_test() {
  // Happy path - empty list
  [#("empty list", [], Ok([]))]
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Happy path - single valid blueprint, artifact params get merged in
  [
    #(
      "single valid blueprint merges artifact params",
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
          params: dict.from_list([
            #("percentile", types.PrimitiveType(types.NumericType(types.Float))),
          ]),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ],
      Ok([
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
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
    blueprints.validate_blueprints(bps, artifacts())
  })

  // No inputs - allowed since blueprints can provide partial inputs
  [
    #(
      "blueprint with no inputs (partial inputs allowed)",
      [
        blueprints.Blueprint(
          name: "minimal",
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - empty params (no blueprint-specific params, only artifact params)
  [
    #(
      "empty params",
      [
        blueprints.Blueprint(
          name: "minimal_params",
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.from_list([#("value", value.StringValue("foobar"))]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
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
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
        blueprints.Blueprint(
          name: "second",
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
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
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
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
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Overshadowing artifact params
  [
    #(
      "cannot overshadow artifact params with blueprint params",
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
          params: dict.from_list([
            #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          ]),
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "blueprint 'success_rate' - overshadowing inherited_params from artifact: threshold",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Empty artifact_refs list
  [
    #(
      "artifact_refs is empty list",
      [
        blueprints.Blueprint(
          name: "no_artifacts",
          artifact_refs: [],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Extra input field
  [
    #(
      "extra input field rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
          params: dict.new(),
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
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Wrong type input value
  [
    #(
      "wrong type input value rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.from_list([#("value", value.IntValue(123))]),
        ),
      ],
      Error(errors.LinkerValueValidationError(
        msg: "Input validation errors: blueprint 'success_rate' - expected (String) received (Int) value (123) for (value)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })
}

// ==== artifact_refs validation ====
// * ✅ duplicate artifact refs rejected
pub fn validate_blueprints_artifact_refs_test() {
  // Duplicate artifact refs
  [
    #(
      "duplicate artifact refs rejected",
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO, SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      Error(errors.LinkerDuplicateError(
        msg: "blueprint 'success_rate' - duplicate artifact references: SLO",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })
}
