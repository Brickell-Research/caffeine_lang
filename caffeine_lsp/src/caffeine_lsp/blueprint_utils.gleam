/// Shared utilities for working with validated blueprints.
/// Used by completion, hover, signature help, and inlay hints.
import caffeine_lang/linker/blueprints.{type Blueprint, type BlueprintValidated}
import caffeine_lang/types.{type AcceptedTypes}
import gleam/dict
import gleam/list
import gleam/set

/// Compute params the expectation must provide — blueprint params minus
/// keys already filled by the blueprint's own inputs.
@internal
pub fn compute_remaining_params(
  blueprint: Blueprint(BlueprintValidated),
) -> dict.Dict(String, AcceptedTypes) {
  let blueprint_input_keys = blueprint.inputs |> dict.keys |> set.from_list
  blueprint.params
  |> dict.filter(fn(key, _) { !set.contains(blueprint_input_keys, key) })
}

/// Build a Dict index from a list of validated blueprints for O(1) name lookups.
@internal
pub fn index_blueprints(
  blueprints: List(Blueprint(BlueprintValidated)),
) -> dict.Dict(String, Blueprint(BlueprintValidated)) {
  blueprints
  |> list.map(fn(b) { #(b.name, b) })
  |> dict.from_list
}
