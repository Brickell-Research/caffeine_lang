import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/artifacts.{type ParamInfo}
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

/// A Blueprint that references one or more Artifacts with parameters and inputs. It provides further params
/// for the Expectation to satisfy while providing a partial set of inputs for the Artifact's params.
/// The phantom type parameter `state` tracks whether the blueprint is `Raw` or `BlueprintValidated`.
pub type Blueprint(state) {
  Blueprint(
    name: String,
    params: dict.Dict(String, AcceptedTypes),
    inputs: dict.Dict(String, Value),
  )
}

/// Validates blueprints against SLO params and merges them.
/// Upgrades the phantom type from `Raw` to `BlueprintValidated` on success.
@internal
pub fn validate_blueprints(
  blueprints: List(Blueprint(Raw)),
  slo_params: dict.Dict(String, ParamInfo),
) -> Result(List(Blueprint(BlueprintValidated)), CompilationError) {
  // Validate all names are unique.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    blueprints,
    by: fn(b) { b.name },
    label: "blueprint names",
  ))

  // Get SLO param types for validation.
  let slo_param_types = artifacts.params_to_types(slo_params)

  // Validate exactly the right number of inputs and each input is the
  // correct type as per the param. A blueprint needs to specify inputs for
  // all required_params from the SLO params.
  let blueprint_slo_params_collection =
    blueprints
    |> list.map(fn(blueprint) { #(blueprint, slo_param_types) })

  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: blueprint_slo_params_collection,
    get_inputs: fn(blueprint) { blueprint.inputs },
    get_params: fn(params) { params },
    with: fn(blueprint) { "blueprint '" <> blueprint.name <> "'" },
    missing_inputs_ok: True,
  ))

  // Ensure no param name overshadowing by the blueprint against SLO params.
  use _ <- result.try(
    validations.validate_no_overshadowing(
      blueprint_slo_params_collection,
      get_check_collection: fn(blueprint) { blueprint.params },
      get_against_collection: fn(params) { params },
      get_error_label: fn(blueprint) {
        "blueprint '"
        <> blueprint.name
        <> "' - overshadowing inherited_params from artifact: "
      },
    ),
  )

  // At this point everything is validated, so we can merge SLO params with blueprint params.
  let merged_param_blueprints =
    blueprints
    |> list.map(fn(blueprint) {
      let all_params =
        slo_param_types
        |> dict.merge(blueprint.params)

      Blueprint(..blueprint, params: all_params)
    })

  Ok(merged_param_blueprints)
}
