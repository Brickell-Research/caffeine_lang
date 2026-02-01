import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/validations
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result

/// An Expectation is a concrete implementation of an Artifact + Blueprint.
pub type Expectation {
  Expectation(
    name: String,
    blueprint_ref: String,
    inputs: dict.Dict(String, Dynamic),
  )
}

/// Validates expectations against blueprints and returns paired with their blueprints.
@internal
pub fn validate_expectations(
  expectations: List(Expectation),
  blueprints: List(Blueprint),
  from source_path: String,
) -> Result(List(#(Expectation, Blueprint)), CompilationError) {
  // Map expectations to blueprints since we'll reuse that numerous times
  // and we've already validated all blueprint_refs.
  let expectations_blueprint_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: blueprints,
      referrers: expectations,
      reference_name: fn(b) { b.name },
      referrer_reference: fn(e) { e.blueprint_ref },
    )

  let #(org, team, service) = helpers.extract_path_prefix(source_path)
  let path_prefix = org <> "." <> team <> "." <> service <> "."

  // Validate that expectation inputs don't overshadow blueprint inputs.
  use _ <- result.try(check_input_overshadowing(
    expectations_blueprint_collection,
    path_prefix,
  ))

  // Validate that expectation.inputs provides params NOT already provided by blueprint.inputs.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: expectations_blueprint_collection,
    get_inputs: fn(expectation) { expectation.inputs },
    get_params: fn(blueprint) {
      let blueprint_input_keys = blueprint.inputs |> dict.keys
      blueprint.params
      |> dict.filter(fn(key, _) { !list.contains(blueprint_input_keys, key) })
    },
    with: fn(expectation) {
      "expectation '" <> path_prefix <> expectation.name <> "'"
    },
    missing_inputs_ok: False,
  ))

  // Validate unique names within a file.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    expectations,
    by: fn(e) { e.name },
    label: "expectation names",
  ))

  Ok(expectations_blueprint_collection)
}

fn check_input_overshadowing(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
  path_prefix: String,
) -> Result(Bool, CompilationError) {
  validations.validate_no_overshadowing(
    expectations_blueprint_collection,
    get_check_collection: fn(expectation) { expectation.inputs },
    get_against_collection: fn(blueprint) { blueprint.inputs },
    get_error_label: fn(expectation) {
      "expectation '"
      <> path_prefix
      <> expectation.name
      <> "' - overshadowing inputs from blueprint: "
    },
  )
}
