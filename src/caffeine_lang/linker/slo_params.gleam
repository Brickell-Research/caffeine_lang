import caffeine_lang/types.{type AcceptedTypes}
import gleam/dict

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
