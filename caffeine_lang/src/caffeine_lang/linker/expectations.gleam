import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/blueprints.{type Blueprint}
import caffeine_lang/linker/validations
import caffeine_lang/string_distance
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

/// An Expectation is a concrete implementation of an Artifact + Blueprint.
pub type Expectation {
  Expectation(
    name: String,
    blueprint_ref: String,
    inputs: dict.Dict(String, Value),
  )
}

/// Validates expectations against blueprints and returns paired with their blueprints.
@internal
pub fn validate_expectations(
  expectations: List(Expectation),
  blueprints: List(Blueprint),
  from source_path: String,
) -> Result(List(#(Expectation, Blueprint)), CompilationError) {
  // Validate that all blueprint_refs exist before mapping.
  use _ <- result.try(validate_blueprint_refs(expectations, blueprints))

  // Map expectations to blueprints since we've validated all blueprint_refs.
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

/// Validates that every expectation's blueprint_ref matches an existing blueprint.
/// Includes Levenshtein-based "did you mean?" suggestions for unknown refs.
fn validate_blueprint_refs(
  expectations: List(Expectation),
  blueprints: List(Blueprint),
) -> Result(Nil, CompilationError) {
  let blueprint_names = list.map(blueprints, fn(b) { b.name })
  let missing =
    expectations
    |> list.filter(fn(e) { !list.contains(blueprint_names, e.blueprint_ref) })
    |> list.map(fn(e) { e.blueprint_ref })

  case missing {
    [] -> Ok(Nil)
    [single_ref] -> {
      let suggestion =
        string_distance.closest_match(single_ref, blueprint_names)
      Error(errors.LinkerParseError(
        msg: "Unknown blueprint reference: " <> single_ref,
        context: errors.ErrorContext(..errors.empty_context(), suggestion:),
      ))
    }
    _ ->
      Error(errors.linker_parse_error(
        msg: "Unknown blueprint reference(s): " <> string.join(missing, ", "),
      ))
  }
}

fn check_input_overshadowing(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
  path_prefix: String,
) -> Result(Nil, CompilationError) {
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
