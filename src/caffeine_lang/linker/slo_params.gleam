import caffeine_lang/types.{type AcceptedTypes}
import gleam/dict
import gleam/set

/// Information about an SLO parameter: its type and a description shown in
/// docs and error messages.
pub type ParamInfo {
  ParamInfo(type_: AcceptedTypes, description: String)
}

/// Extracts just the types from SLO params, discarding descriptions.
/// Useful when downstream code only needs type information.
@internal
pub fn params_to_types(
  params: dict.Dict(String, ParamInfo),
) -> dict.Dict(String, AcceptedTypes) {
  params
  |> dict.map_values(fn(_, param_info) { param_info.type_ })
}

/// The params an unmeasured expectation is allowed to provide.
/// Used by both validation and IR construction to keep the two in sync.
@internal
pub const unmeasured_param_keys = ["threshold", "window_in_days", "depends_on"]

/// Derives the restricted param types for unmeasured expectations from SLO params.
@internal
pub fn unmeasured_param_types(
  slo_params: dict.Dict(String, ParamInfo),
) -> dict.Dict(String, AcceptedTypes) {
  let allowed = set.from_list(unmeasured_param_keys)
  slo_params
  |> dict.filter(fn(key, _) { set.contains(allowed, key) })
  |> params_to_types()
}
