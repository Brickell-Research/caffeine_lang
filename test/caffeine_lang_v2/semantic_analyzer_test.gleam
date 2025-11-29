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
      #("value", "numerator / denominator"),
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
      #("environment", "production"),
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
// ## SLO Specific - Queries (handled by CQL, outside of these checks) ##
// * ❌ too few params compared to value
// * ❌ too many params compared to value
// * ❌ different params compared to value
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
// * ❌ base_params and params have no key collisions (same param name in both)

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
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Template Validation ##
// * ❌ template variable references non-existent blueprint param (${undefined_var})
// * ❌ invalid template syntax (malformed ${...})
// * ❌ blueprint params key collision/shadowing with artifact's base_params
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
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Additional Input Validation ##
// * ❌ inputs for non-existent blueprint params (extra/unknown inputs)
// * ❌ type coercion validation (e.g., "abc" when Integer expected)
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
// ==== Cross-Cutting / Chain Validation ====
// * ❌ full valid chain: Artifact → Blueprint → Expectation (success case)
// * ❌ base_params types propagate correctly through blueprint to expectation
// * ❌ expectation input coercible to artifact base_params type
// * ❌ expectation names unique across all expectation files (linker handles per-file)
// * ❌ blueprint names unique across all blueprint files (parser handles per-file)

// ==== Type-Specific Validation ====
// * ❌ expected Boolean, got other scalar
// * ❌ expected Integer, got Float
// * ❌ expected String, got numeric
// * ❌ expected NonEmptyList(T), got scalar
// * ❌ empty list for NonEmptyList(T)
// * ❌ expected Optional(T), got wrong inner type
// * ❌ expected Dict(String, T), got scalar

// ==== Default/Optional Handling ====
// * ❌ optional param omitted → uses default
// * ❌ optional param provided → overrides default
// * ❌ default via -> operator parsed and applied
