import caffeine_lang_v2/common/ast
import caffeine_lang_v2/generator
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints
import caffeine_lang_v2/parser/expectations
import gleam/dict
import gleeunit/should
import simplifile

fn artifact_helper() -> Artifact {
  let assert Ok(art) =
    artifacts.make_artifact(
      name: "slo",
      version: "1.0.0",
      base_params: dict.new(),
      params: dict.new(),
    )

  art
}

fn blueprint_helper(
  name name: String,
  value value: String,
) -> blueprints.Blueprint {
  blueprints.Blueprint(
    name:,
    artifact: "slo",
    inputs: dict.from_list([#("value", value)]),
    params: dict.new(),
  )
}

fn expectation_helper(
  name name: String,
  blueprint blueprint: String,
  threshold threshold: String,
  window_in_days window_in_days: String,
) -> expectations.Expectation {
  expectations.Expectation(
    name:,
    blueprint:,
    inputs: dict.from_list([
      #("threshold", threshold),
      #("window_in_days", window_in_days),
    ]),
  )
}

const generator_tests_path = "test/caffeine_lang_v2/artifacts/generator_tests/"

// ==== generate ====
// * ✅ Single expectation generates provider + one resource
// * ✅ Multiple expectations across multiple blueprints
pub fn happy_path_single_expectation_test() {
  let ast =
    ast.AST(
      artifacts: [artifact_helper()],
      blueprints: [
        blueprint_helper(
          name: "blueprint_1",
          value: "\"sum:requests.success{*}\"",
        ),
      ],
      expectations: [
        expectation_helper(
          name: "expectation_1",
          blueprint: "blueprint_1",
          threshold: "99.9",
          window_in_days: "30",
        ),
      ],
    )

  let assert Ok(expected) =
    simplifile.read(generator_tests_path <> "happy_path_single_expectation.tf")

  generator.generate(ast)
  |> should.equal(Ok(expected))

  let ast =
    ast.AST(
      artifacts: [artifact_helper()],
      blueprints: [
        blueprint_helper(
          name: "availability_blueprint",
          value: "\"sum:requests.success{*}\"",
        ),
        blueprint_helper(
          name: "latency_blueprint",
          value: "\"avg:requests.latency{*}\"",
        ),
      ],
      expectations: [
        expectation_helper(
          name: "api_availability",
          blueprint: "availability_blueprint",
          threshold: "99.9",
          window_in_days: "30",
        ),
        expectation_helper(
          name: "api_latency",
          blueprint: "latency_blueprint",
          threshold: "95.0",
          window_in_days: "7",
        ),
        expectation_helper(
          name: "checkout_availability",
          blueprint: "availability_blueprint",
          threshold: "99.5",
          window_in_days: "30",
        ),
      ],
    )

  let assert Ok(expected) =
    simplifile.read(
      generator_tests_path <> "happy_path_multiple_expectations.tf",
    )

  generator.generate(ast)
  |> should.equal(Ok(expected))
}
