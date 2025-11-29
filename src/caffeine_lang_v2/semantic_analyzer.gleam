import caffeine_lang_v2/common/ast.{type AST}
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/dict
import gleam/list
import gleam/result

pub fn perform(abs_syn_tree: AST) -> Result(Bool, String) {
  let arts = abs_syn_tree.artifacts
  let bluprts = abs_syn_tree.blueprints
  let expcts = abs_syn_tree.expectations

  let blueprints_map =
    abs_syn_tree.blueprints
    |> list.map(fn(blueprint) { #(blueprints.get_name(blueprint), blueprint) })
    |> dict.from_list

  let artifacts_map =
    abs_syn_tree.artifacts
    |> list.map(fn(artifact) { #(artifacts.get_name(artifact), artifact) })
    |> dict.from_list

  use _ <- result.try(perform_sanity_checks(arts, bluprts, expcts))

  perform_reference_checks(artifacts_map, blueprints_map, bluprts, expcts)
}

fn perform_sanity_checks(
  artifacts: List(Artifact),
  blueprints: List(Blueprint),
  expectations: List(Expectation),
) -> Result(Bool, String) {
  // sanity check - at least one of each
  case artifacts, blueprints, expectations {
    [], _, _ -> Error("Expected at least one artifact.")
    _, [], _ -> Error("Expected at least one blueprint.")
    _, _, [] -> Error("Expected at least one expectation.")
    _, _, _ -> Ok(True)
  }
}

fn perform_reference_checks(
  artifacts_map: dict.Dict(String, Artifact),
  blueprints_map: dict.Dict(String, Blueprint),
  blueprints: List(Blueprint),
  expectations: List(Expectation),
) -> Result(Bool, String) {
  let not_missing_refs = fn(
    parents_map: dict.Dict(String, a),
    children: List(b),
    name_fn: fn(b) -> String,
  ) -> Bool {
    children
    |> list.all(fn(child) { dict.has_key(parents_map, name_fn(child)) })
  }

  // reference check for blueprint -> artifact and expectation -> blueprint
  let not_missing_expectation_to_blueprint_reference =
    not_missing_refs(blueprints_map, expectations, fn(a) {
      expectations.get_blueprint(a)
    })
  let not_missing_blueprint_to_artifact_reference =
    not_missing_refs(artifacts_map, blueprints, fn(a) {
      blueprints.get_artifact(a)
    })

  case
    not_missing_blueprint_to_artifact_reference,
    not_missing_expectation_to_blueprint_reference
  {
    False, _ ->
      Error("At least one blueprint is referencing a non-existent artifact.")
    _, False ->
      Error("At least one expectation is referencing a non-existent blueprint.")
    _, _ -> Ok(True)
  }
}
