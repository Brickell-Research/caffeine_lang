import caffeine_lang_v2/common/ast.{type AST}
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import caffeine_lang_v2/parser/expectations.{type Expectation}
import gleam/dict
import gleam/list
import gleam/result
import gleam/set
import gleam/string

pub fn perform(abs_syn_tree: AST) -> Result(Bool, String) {
  let arts = abs_syn_tree.artifacts
  let bluprts = abs_syn_tree.blueprints
  let expcts = abs_syn_tree.expectations

  let artifacts_map =
    abs_syn_tree.artifacts
    |> list.map(fn(artifact) { #(artifacts.get_name(artifact), artifact) })
    |> dict.from_list

  let unresolved_blueprints_map =
    abs_syn_tree.blueprints
    |> list.map(fn(blueprint) { #(blueprints.get_name(blueprint), blueprint) })
    |> dict.from_list

  use _ <- result.try(perform_sanity_checks(arts, bluprts, expcts))

  use _ <- result.try(perform_reference_checks(
    artifacts_map,
    unresolved_blueprints_map,
    bluprts,
    expcts,
  ))

  use _ <- result.try(perform_shadowing_checks(artifacts_map, bluprts))

  let resolved_blueprints_map =
    abs_syn_tree.blueprints
    |> list.map(fn(blueprint) {
      let assert Ok(refd_artifact) =
        dict.get(artifacts_map, blueprints.get_artifact(blueprint))

      #(
        blueprints.get_name(blueprint),
        blueprints.set_params(
          blueprint,
          dict.merge(
            blueprints.get_params(blueprint),
            artifacts.get_base_params(refd_artifact),
          ),
        ),
      )
    })
    |> dict.from_list

  perform_input_validation_checks(
    artifacts_map,
    resolved_blueprints_map,
    bluprts,
    expcts,
  )
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

  // TODO: better error messages
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

// As of writing (11/29/25) we _do not_ allow param overrides/shadowing between the
// artifacts and blueprints.
fn perform_shadowing_checks(
  artifacts_map: dict.Dict(String, Artifact),
  blueprints: List(Blueprint),
) -> Result(Bool, String) {
  let illegally_shadowing_blueprints =
    blueprints
    |> list.filter_map(fn(blueprint) {
      let assert Ok(refd_artifact) =
        dict.get(artifacts_map, blueprints.get_artifact(blueprint))

      let base_params =
        refd_artifact |> artifacts.get_base_params |> dict.keys |> set.from_list
      let blueprint_params =
        blueprint |> blueprints.get_params |> dict.keys |> set.from_list

      let shadowing_exists =
        !{ set.intersection(base_params, blueprint_params) |> set.is_empty }

      case shadowing_exists {
        True -> Ok(blueprints.get_name(blueprint))
        False -> Error(Nil)
      }
    })
    |> string.join(", ")

  case illegally_shadowing_blueprints {
    "" -> Ok(True)
    _ ->
      Error(
        "The following blueprints illegally overshadow one or more of their artifact's params: "
        <> illegally_shadowing_blueprints,
      )
  }
}

fn perform_input_validation_checks(
  artifacts_map: dict.Dict(String, Artifact),
  blueprints_map: dict.Dict(String, Blueprint),
  blueprints: List(Blueprint),
  expectations: List(Expectation),
) -> Result(Bool, String) {
  // expectations have exactly the right inputs for blueprint params
  let expectation_assertion_string =
    assert_inputs_sensible_for_params(
      children: expectations,
      parents_map: blueprints_map,
      get_parent_ref: expectations.get_blueprint,
      get_params: blueprints.get_params,
      get_inputs: expectations.get_inputs,
      get_child_name: expectations.get_name,
      get_parent_name: blueprints.get_name,
    )

  // blueprints have exactly the right inputs for artifacts params
  let blueprint_assertion_string =
    assert_inputs_sensible_for_params(
      children: blueprints,
      parents_map: artifacts_map,
      get_parent_ref: blueprints.get_artifact,
      get_params: artifacts.get_params,
      get_inputs: blueprints.get_inputs,
      get_child_name: blueprints.get_name,
      get_parent_name: artifacts.get_name,
    )

  case expectation_assertion_string, blueprint_assertion_string {
    "", "" -> Ok(True)
    msg, "" -> Error(msg)
    "", msg -> Error(msg)
    msg, msg2 -> Error(msg <> " and " <> msg2)
  }
}

fn assert_inputs_sensible_for_params(
  children children: List(a),
  parents_map parents_map: dict.Dict(String, b),
  get_parent_ref get_parent_ref: fn(a) -> String,
  get_params get_params: fn(b) -> dict.Dict(String, helpers.AcceptedTypes),
  get_inputs get_inputs: fn(a) -> dict.Dict(String, String),
  get_child_name get_child_name: fn(a) -> String,
  get_parent_name get_parent_name: fn(b) -> String,
) -> String {
  children
  |> list.map(fn(child) {
    let assert Ok(refd_parent) = dict.get(parents_map, get_parent_ref(child))

    let expected_input_attributes =
      set.from_list({ get_params(refd_parent) |> dict.keys })
    let actual_input_attributes =
      set.from_list({ get_inputs(child) |> dict.keys })

    // difference means present in the first (expected) but not the second (actual)
    let missing_inputs =
      set.difference(expected_input_attributes, actual_input_attributes)
      |> set.to_list

    // difference means present in the first (actual) but not the second (expected)
    let extra_inputs =
      set.difference(actual_input_attributes, expected_input_attributes)
      |> set.to_list

    let error_msg_suffic =
      " in child: "
      <> child |> get_child_name
      <> " against parent: "
      <> refd_parent |> get_parent_name

    // TODO: better error messages
    case missing_inputs, extra_inputs {
      [], [] -> Ok(True)
      _, [] -> Error("Missing attributes" <> error_msg_suffic)
      [], _ -> Error("Extra attributes" <> error_msg_suffic)
      _, _ -> Error("Missing and extra attributes" <> error_msg_suffic)
    }
  })
  |> list.filter_map(fn(res) {
    case res {
      Ok(_) -> Error(Nil)
      Error(msg) -> Ok(msg)
    }
  })
  |> string.join(", ")
}
