import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/validations
import caffeine_lang/types.{type AcceptedTypes}
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/result

/// Marker type for blueprints that have not yet been validated.
pub type Raw

/// Marker type for blueprints that have passed validation.
pub type BlueprintValidated

/// A Blueprint with parameters and inputs.
/// The phantom type parameter `state` tracks whether the blueprint is `Raw` or `BlueprintValidated`.
pub type Blueprint(state) {
  Blueprint(
    name: String,
    params: dict.Dict(String, AcceptedTypes),
    inputs: dict.Dict(String, Value),
  )
}

/// Validates blueprints: checks name uniqueness and input correctness.
/// Upgrades the phantom type from `Raw` to `BlueprintValidated` on success.
@internal
pub fn validate_blueprints(
  blueprints: List(Blueprint(Raw)),
) -> Result(List(Blueprint(BlueprintValidated)), CompilationError) {
  // Validate all names are unique.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    blueprints,
    by: fn(b) { b.name },
    label: "blueprint names",
  ))

  // Validate inputs match the blueprint's own params.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: blueprints
      |> list.map(fn(blueprint) { #(blueprint, blueprint.params) }),
    get_inputs: fn(blueprint) { blueprint.inputs },
    get_params: fn(params) { params },
    with: fn(blueprint) { "blueprint '" <> blueprint.name <> "'" },
    missing_inputs_ok: True,
  ))

  // Promote to BlueprintValidated.
  let validated =
    blueprints
    |> list.map(fn(blueprint) {
      Blueprint(
        name: blueprint.name,
        params: blueprint.params,
        inputs: blueprint.inputs,
      )
    })

  Ok(validated)
}
