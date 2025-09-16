import caffeine_lang/phase_1/parser/utils/general_common
import caffeine_lang/phase_1/parser/utils/glaml_helpers
import caffeine_lang/types/instantiation_types.{
  type UnresolvedSlo, type UnresolvedTeam, UnresolvedSlo, UnresolvedTeam,
}
import glaml
import gleam/dict
import gleam/result

// ==== Public ====
/// Parses an instantiation from a YAML file. This is a single team with at least one slo.
/// Note that within a configutation repository, there can be multiple instantiations for
/// the same team and even the same service. Logic for this lives within the linking code.
pub fn parse_team_instantiation(
  file_path: String,
) -> Result(UnresolvedTeam, String) {
  use params <- result.try(general_common.extract_params_from_file_path(
    file_path,
  ))
  let assert Ok(team_name) = dict.get(params, "team_name")

  use slos <- result.try(parse_slos_instantiation(file_path, params))

  Ok(UnresolvedTeam(name: team_name, slos: slos))
}

pub fn parse_slos_instantiation(
  file_path: String,
  params: dict.Dict(String, String),
) -> Result(List(UnresolvedSlo), String) {
  glaml_helpers.parse_specification(file_path, params, parse_slo, "slos")
}

// ==== Private ====
/// Parses a single SLO.
fn parse_slo(
  slo: glaml.Node,
  params: dict.Dict(String, String),
) -> Result(UnresolvedSlo, String) {
  use sli_type <- result.try(glaml_helpers.extract_string_from_node(
    slo,
    "sli_type",
  ))
  use filters <- result.try(glaml_helpers.extract_dict_strings_from_node(
    slo,
    "filters",
  ))
  use threshold <- result.try(glaml_helpers.extract_float_from_node(
    slo,
    "threshold",
  ))
  use window_in_days <- result.try(glaml_helpers.extract_int_from_node(
    slo,
    "window_in_days",
  ))

  let assert Ok(service_name) = dict.get(params, "service_name")

  Ok(UnresolvedSlo(
    sli_type: sli_type,
    filters: filters,
    threshold: threshold,
    service_name: service_name,
    window_in_days: window_in_days,
  ))
}
