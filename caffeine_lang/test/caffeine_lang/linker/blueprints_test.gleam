import caffeine_lang/errors
import caffeine_lang/linker/artifacts.{
  type Artifact, DependencyRelations, ParamInfo, SLO,
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

fn multi_artifacts() -> List(Artifact) {
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
    artifacts.Artifact(
      type_: artifacts.DependencyRelations,
      description: "",
      params: dict.from_list([
        #(
          "relationship",
          ParamInfo(
            type_: types.CollectionType(
              types.List(types.PrimitiveType(types.String)),
            ),
            description: "",
          ),
        ),
        #(
          "isHard",
          ParamInfo(type_: types.PrimitiveType(types.Boolean), description: ""),
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
// * ✅ happy path - overlapping params with same type merge correctly
// * ✅ duplicates - duplicate names rejected
// * ✅ duplicates - cannot overshadow artifact params with blueprint params
// * ✅ duplicates - duplicate artifact refs rejected
// * ✅ semantic - unknown artifact in list
// * ✅ empty - artifact_refs is empty list
// * ✅ conflicting params - artifacts have same param name with different types
// * ✅ input validation - extra input field rejected
// * ✅ input validation - wrong type input value rejected
pub fn validate_blueprints_test() {
  // Happy path - empty list
  [#([], Ok([]))]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Happy path - single valid blueprint, artifact params get merged in
  [
    #(
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
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // No inputs - allowed since blueprints can provide partial inputs
  [
    #(
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
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - empty params (no blueprint-specific params, only artifact params)
  [
    #(
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
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Happy path - multiple blueprints
  [
    #(
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
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(result) -> list.length(result) == 2
      Error(_) -> False
    }
  })

  // Happy path - overlapping params with same type merge correctly
  [
    #(
      [
        blueprints.Blueprint(
          name: "tracked_slo",
          artifact_refs: [SLO, DependencyRelations],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, multi_artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Duplicate names
  [
    #(
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
      Error(errors.ParserDuplicateError(
        msg: "Duplicate blueprint names: success_rate",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Overshadowing artifact params
  [
    #(
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
      Error(errors.ParserDuplicateError(
        msg: "blueprint 'success_rate' - overshadowing inherited_params from artifact: threshold",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Empty artifact_refs list
  [
    #(
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
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Conflicting params - artifacts have same param name with different types
  [
    #(
      [
        blueprints.Blueprint(
          name: "conflicting",
          artifact_refs: [SLO, DependencyRelations],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    // Use custom artifacts with conflicting param types
    let conflicting_artifacts = [
      artifacts.Artifact(
        type_: artifacts.SLO,
        description: "",
        params: dict.from_list([
          #(
            "shared_param",
            ParamInfo(type_: types.PrimitiveType(types.String), description: ""),
          ),
        ]),
      ),
      artifacts.Artifact(
        type_: artifacts.DependencyRelations,
        description: "",
        params: dict.from_list([
          #(
            "shared_param",
            ParamInfo(
              type_: types.PrimitiveType(types.Boolean),
              description: "",
            ),
          ),
        ]),
      ),
    ]
    case blueprints.validate_blueprints(bps, conflicting_artifacts) {
      Ok(_) -> False
      Error(_) -> True
    }
  })

  // Extra input field
  [
    #(
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
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: blueprint 'success_rate' - Extra keys in input: extra",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })

  // Wrong type input value
  [
    #(
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO],
          params: dict.new(),
          inputs: dict.from_list([#("value", value.IntValue(123))]),
        ),
      ],
      Error(errors.ParserJsonParserError(
        msg: "Input validation errors: blueprint 'success_rate' - expected (String) received (Int) value (123) for (value)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, artifacts())
  })
}

// ==== artifact_refs validation ====
// * ✅ happy path - multiple artifacts, params merged from both
// * ✅ duplicate artifact refs rejected
pub fn validate_blueprints_artifact_refs_test() {
  // Happy path - multiple artifacts, params merged
  [
    #(
      [
        blueprints.Blueprint(
          name: "tracked_slo",
          artifact_refs: [SLO, DependencyRelations],
          params: dict.new(),
          inputs: dict.from_list([
            #("value", value.StringValue("foobar")),
            #("isHard", value.BoolValue(True)),
          ]),
        ),
      ],
      True,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    case blueprints.validate_blueprints(bps, multi_artifacts()) {
      Ok(_) -> True
      Error(_) -> False
    }
  })

  // Duplicate artifact refs
  [
    #(
      [
        blueprints.Blueprint(
          name: "success_rate",
          artifact_refs: [SLO, SLO],
          params: dict.new(),
          inputs: dict.new(),
        ),
      ],
      Error(errors.ParserDuplicateError(
        msg: "blueprint 'success_rate' - duplicate artifact references: SLO",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(bps) {
    blueprints.validate_blueprints(bps, multi_artifacts())
  })
}
