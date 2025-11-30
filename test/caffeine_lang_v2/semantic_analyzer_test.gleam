import caffeine_lang_v2/common/ast
import caffeine_lang_v2/common/helpers.{type AcceptedTypes}
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import caffeine_lang_v2/semantic_analyzer
import gleam/dict
import gleeunit/should

fn default_artifact() -> Artifact {
  let base_params =
    dict.from_list([
      #("threshold", helpers.Float),
      #("window_in_days", helpers.Optional(helpers.Integer)),
    ])
  let params =
    dict.from_list([
      #("value", helpers.String),
    ])

  artifact_helper("artifact_1", base_params, params)
}

fn artifact_helper(
  name: String,
  base_params: dict.Dict(String, AcceptedTypes),
  params: dict.Dict(String, AcceptedTypes),
) -> Artifact {
  let assert Ok(art) =
    artifacts.make_artifact(name:, version: "1.0.0", base_params:, params:)

  art
}

fn default_blueprint() -> Blueprint {
  let params = dict.from_list([#("environment", helpers.String)])
  let inputs =
    dict.from_list([
      #("value", "\"numerator / denominator\""),
    ])

  blueprint_helper("blueprint_1", "artifact_1", inputs, params)
}

fn blueprint_helper(
  name: String,
  artifact: String,
  inputs: dict.Dict(String, String),
  params: dict.Dict(String, AcceptedTypes),
) {
  blueprints.make_blueprint(name:, artifact:, params:, inputs:)
}

fn default_expectation() -> Expectation {
  let inputs =
    dict.from_list([
      #("environment", "\"production\""),
      #("threshold", "99.9"),
      #("window_in_days", "10"),
    ])

  expectation_helper("expectation_1", "blueprint_1", inputs)
}

fn expectation_helper(
  name: String,
  blueprint: String,
  inputs: dict.Dict(String, String),
) {
  expectations.make_service_expectation(name:, blueprint:, inputs:)
}

// ==== Artifacts ====
// ## SLO Specific - Sanity (technically input from lower configs) ##
// * ✅ need at least one artifact
// * ❌ threshold within a reasonable range
// * ❌ threshold correct type
// * ❌ window_in_days within a reasonable range/set
// * ❌ window_in_days correct type
// * ❌ window_in_days defaults as expected
pub fn artifacts_sanity_test() {
  let _artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  // happy path: blueprint referenced by expectation exists
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [], blueprints: [
      blueprint,
    ]),
  )
  |> should.equal(Error("Expected at least one artifact."))
}

// ## Cross-Field Validation ##
// * ✅ base_params and params have no key collisions (same param name in both)
pub fn blueprints_do_not_overshadow_artifact_base_params_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  let shadowing_params = dict.from_list([#("window_in_days", helpers.String)])
  let further_shadowing_params =
    dict.from_list([
      #("window_in_days", helpers.String),
      #("thresold", helpers.String),
    ])

  // overshadow a single param in a single blueprint
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_params(blueprint, shadowing_params),
    ]),
  )
  |> should.equal(Error(
    "The following blueprints illegally overshadow one or more of their artifact's params: "
    <> blueprints.get_name(blueprint),
  ))

  // overshadow a single param in a single blueprint and two params in a second blueprint
  let blueprint_2 =
    blueprint
    |> blueprints.set_name("blueprint_2")
    |> blueprints.set_params(further_shadowing_params)

  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_params(blueprint, shadowing_params),
      blueprint_2,
    ]),
  )
  |> should.equal(Error(
    "The following blueprints illegally overshadow one or more of their artifact's params: "
    <> blueprints.get_name(blueprint)
    <> ", "
    <> blueprints.get_name(blueprint_2),
  ))
}

// ==== Blueprints ====
// ## Reference Validation ##
// * ✅ artifact referenced by blueprint exists (success case)
// * ✅ artifact referenced by blueprint does not exist (error case)
pub fn blueprints_reference_validation_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  // happy path: artifact referenced by blueprint exists
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprint,
    ]),
  )
  |> should.equal(Ok(True))

  // sad path: artifact referenced by blueprint DOES NOT exist
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_artifact(blueprint, "non-existent-artifact"),
    ]),
  )
  |> should.equal(Error(
    "At least one blueprint is referencing a non-existent artifact.",
  ))
}

// ## Inputs vs Artifact Params ##
// * ✅ missing inputs
// * ✅ extra inputs
// * ✅ missing and extra inputs
// * ✅ wrong type in inputs
pub fn blueprints_input_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  // missing inputs
  let empty_inputs = dict.new()
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_inputs(blueprint, empty_inputs),
    ]),
  )
  |> should.equal(Error(
    "Missing attributes in child: blueprint_1 against parent: artifact_1",
  ))

  // extra inputs
  let extra_inputs =
    dict.from_list([#("value", "\"production\""), #("extra", "foobar")])

  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_inputs(blueprint, extra_inputs),
    ]),
  )
  |> should.equal(Error(
    "Extra attributes in child: blueprint_1 against parent: artifact_1",
  ))

  // missing and extra inputs
  let missing_and_extra_inputs = dict.from_list([#("extra", "foobar")])

  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_inputs(blueprint, missing_and_extra_inputs),
    ]),
  )
  |> should.equal(Error(
    "Missing and extra attributes in child: blueprint_1 against parent: artifact_1",
  ))

  // wrong type in inputs
  let wrong_type_in_input = dict.from_list([#("value", "10")])

  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprints.set_inputs(blueprint, wrong_type_in_input),
    ]),
  )
  |> should.equal(Error(
    "Incorrect type for value. Received: 10 and expected a String. A string is defined as between two (and only two) double quotes",
  ))
}

// ## Template Validation ##
// * ❌ template variable references non-existent blueprint param (${undefined_var})
// * ❌ invalid template syntax (malformed ${...})
// ## Sanity ##
// * ✅ need at least one blueprint
pub fn blueprints_sanity_test() {
  let artifact = default_artifact()
  let _blueprint = default_blueprint()
  let expectation = default_expectation()

  // happy path: blueprint referenced by expectation exists
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: []),
  )
  |> should.equal(Error("Expected at least one blueprint."))
}

// ==== Expectations ====
// ## Reference Validation ##
// * ✅ blueprint referenced by expectation exists (success case)
// * ✅ blueprint referenced by expectation does not exist (error case)
pub fn expectations_reference_validation_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  // happy path: blueprint referenced by expectation exists
  semantic_analyzer.perform(
    ast.AST(expectations: [expectation], artifacts: [artifact], blueprints: [
      blueprint,
    ]),
  )
  |> should.equal(Ok(True))

  // sad path: blueprint referenced by expectation DOES NOT exist
  semantic_analyzer.perform(
    ast.AST(
      expectations: [
        expectations.set_blueprint(expectation, "non-existent-blueprint"),
      ],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "At least one expectation is referencing a non-existent blueprint.",
  ))
}

// ## Inputs vs Blueprint Params ##
// * ✅ missing inputs 
// * ✅ extra inputs
// * ✅ missing and extra inputs
// * ✅ wrong type in inputs
pub fn expectations_input_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let expectation = default_expectation()

  // missing inputs - general
  let empty_inputs = dict.new()
  semantic_analyzer.perform(
    ast.AST(
      expectations: [expectations.set_inputs(expectation, empty_inputs)],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Missing attributes in child: expectation_1 against parent: blueprint_1",
  ))

  // missing inputs - only against blueprint
  let missing_blueprint_params =
    dict.from_list([
      #("threshold", "99.9"),
      #("window_in_days", "10"),
    ])
  semantic_analyzer.perform(
    ast.AST(
      expectations: [
        expectations.set_inputs(expectation, missing_blueprint_params),
      ],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Missing attributes in child: expectation_1 against parent: blueprint_1",
  ))

  // missing inputs - only against artifact (base_params)
  let missing_base_params =
    dict.from_list([
      #("environment", "\"production\""),
    ])
  semantic_analyzer.perform(
    ast.AST(
      expectations: [expectations.set_inputs(expectation, missing_base_params)],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Missing attributes in child: expectation_1 against parent: blueprint_1",
  ))

  // extra inputs
  let extra_inputs =
    dict.from_list([
      #("threshold", "99.9"),
      #("window_in_days", "10"),
      #("environment", "\"production\""),
      #("extra", "foobar"),
    ])

  semantic_analyzer.perform(
    ast.AST(
      expectations: [expectations.set_inputs(expectation, extra_inputs)],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Extra attributes in child: expectation_1 against parent: blueprint_1",
  ))

  // missing and extra inputs
  let missing_and_extra_inputs = dict.from_list([#("extra", "foobar")])

  semantic_analyzer.perform(
    ast.AST(
      expectations: [
        expectations.set_inputs(expectation, missing_and_extra_inputs),
      ],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Missing and extra attributes in child: expectation_1 against parent: blueprint_1",
  ))

  // wrong type in inputs - artitact (base_params)
  let wrong_type_in_inputs_for_artifact =
    dict.from_list([
      #("environment", "\"production\""),
      #("threshold", "99.9"),
      #("window_in_days", "foo"),
    ])

  semantic_analyzer.perform(
    ast.AST(
      expectations: [
        expectations.set_inputs(expectation, wrong_type_in_inputs_for_artifact),
      ],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Incorrect type for window_in_days. Received: foo and expected a Optional(Integer)",
  ))

  // wrong type in inputs - blueprint
  let wrong_type_in_inputs_for_blueprint =
    dict.from_list([
      #("environment", "21"),
      #("threshold", "99.9"),
      #("window_in_days", "10"),
    ])

  semantic_analyzer.perform(
    ast.AST(
      expectations: [
        expectations.set_inputs(expectation, wrong_type_in_inputs_for_blueprint),
      ],
      artifacts: [artifact],
      blueprints: [
        blueprint,
      ],
    ),
  )
  |> should.equal(Error(
    "Incorrect type for environment. Received: 21 and expected a String. A string is defined as between two (and only two) double quotes",
  ))
}

// ## Sanity ##
// * ✅ need at least one expectation
pub fn expectations_sanity_test() {
  let artifact = default_artifact()
  let blueprint = default_blueprint()
  let _expectation = default_expectation()

  // happy path: blueprint referenced by expectation exists
  semantic_analyzer.perform(
    ast.AST(expectations: [], artifacts: [artifact], blueprints: [blueprint]),
  )
  |> should.equal(Error("Expected at least one expectation."))
}

// ==== Type-Specific Validation ====
// * ✅ Booleans
// * ✅ Integers
// * ✅ Floats
// * ✅ NonEmptyList(T)'s
// * ✅ Optional(T)'s
// * ✅ Dict(String, T)'s
pub fn assert_raw_value_correct_type_test() {
  // ## Bool ##
  // - sad path
  semantic_analyzer.assert_value_is_as_expected("10", helpers.Boolean)
  |> should.equal(Error("Received: 10 and expected a Bool"))
  // - happy path
  semantic_analyzer.assert_value_is_as_expected("true", helpers.Boolean)
  |> should.equal(Ok(True))

  // ## Integer
  // - sad path
  semantic_analyzer.assert_value_is_as_expected("10.0", helpers.Integer)
  |> should.equal(Error("Received: 10.0 and expected an Integer"))
  // - happy path
  semantic_analyzer.assert_value_is_as_expected("10", helpers.Integer)
  |> should.equal(Ok(True))

  // ## Float ##
  // - sad path: string that's not a number
  semantic_analyzer.assert_value_is_as_expected("abc", helpers.Float)
  |> should.equal(Error("Received: abc and expected a Float"))
  // - happy path: valid float
  semantic_analyzer.assert_value_is_as_expected("10.5", helpers.Float)
  |> should.equal(Ok(True))
  // - happy path: integer is also valid float
  semantic_analyzer.assert_value_is_as_expected("10", helpers.Float)
  |> should.equal(Error("Received: 10 and expected a Float"))

  // ## String ##
  // - sad path: no quotes
  semantic_analyzer.assert_value_is_as_expected("hello world", helpers.String)
  |> should.equal(Error(
    "Received: hello world and expected a String. A string is defined as between two (and only two) double quotes",
  ))
  // - sad path: only front quote
  semantic_analyzer.assert_value_is_as_expected("\"hello world", helpers.String)
  |> should.equal(Error(
    "Received: \"hello world and expected a String. A string is defined as between two (and only two) double quotes",
  ))
  // - sad path: only end quote
  semantic_analyzer.assert_value_is_as_expected("hello world\"", helpers.String)
  |> should.equal(Error(
    "Received: hello world\" and expected a String. A string is defined as between two (and only two) double quotes",
  ))
  // - sad path: more than two quotes
  semantic_analyzer.assert_value_is_as_expected(
    "\"hello\"world\"",
    helpers.String,
  )
  |> should.equal(Error(
    "Received: \"hello\"world\" and expected a String. A string is defined as between two (and only two) double quotes",
  ))
  // - happy path
  semantic_analyzer.assert_value_is_as_expected(
    "\"hello world\"",
    helpers.String,
  )
  |> should.equal(Ok(True))

  // ## NonEmptyList(T) ##
  // - sad path: empty list
  semantic_analyzer.assert_value_is_as_expected(
    "[]",
    helpers.NonEmptyList(helpers.String),
  )
  |> should.equal(Error("Received: [] and expected a NonEmptyList"))
  // - sad path: wrong inner type
  semantic_analyzer.assert_value_is_as_expected(
    "[1, 2, 3]",
    helpers.NonEmptyList(helpers.String),
  )
  |> should.equal(Error(
    "Received: [1, 2, 3] and expected a NonEmptyList(String)",
  ))
  // - happy path: non-empty list with correct inner type
  semantic_analyzer.assert_value_is_as_expected(
    "[\"a\", \"b\"]",
    helpers.NonEmptyList(helpers.String),
  )
  |> should.equal(Ok(True))

  // ## Optional(T) ##
  // - sad path: wrong inner type when value is present
  semantic_analyzer.assert_value_is_as_expected(
    "abc",
    helpers.Optional(helpers.Integer),
  )
  |> should.equal(Error("Received: abc and expected a Optional(Integer)"))
  // - happy path: valid inner type
  semantic_analyzer.assert_value_is_as_expected(
    "42",
    helpers.Optional(helpers.Integer),
  )
  |> should.equal(Ok(True))
  // - happy path: null/empty is valid for optional
  semantic_analyzer.assert_value_is_as_expected(
    "null",
    helpers.Optional(helpers.Integer),
  )
  |> should.equal(Ok(True))

  // ## Dict(String, T) ##
  // - sad path: scalar instead of dict
  semantic_analyzer.assert_value_is_as_expected(
    "hello",
    helpers.Dict(helpers.String, helpers.Integer),
  )
  |> should.equal(Error("Received: hello and expected a Dict"))
  // - sad path: wrong value type in dict
  semantic_analyzer.assert_value_is_as_expected(
    "{\"key\": \"not_an_int\"}",
    helpers.Dict(helpers.String, helpers.Integer),
  )
  |> should.equal(Error(
    "Received: {\"key\": \"not_an_int\"} and expected a Dict(String, Integer)",
  ))
  // - happy path: valid dict with correct types
  semantic_analyzer.assert_value_is_as_expected(
    "{\"key\": 42}",
    helpers.Dict(helpers.String, helpers.Integer),
  )
  |> should.equal(Ok(True))
}
// ==== Default/Optional Handling ====
// * ❌ optional param omitted → uses default
// * ❌ optional param provided → overrides default
// * ❌ default via -> operator parsed and applied
