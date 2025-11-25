import caffeine_lang/phase_1/parser/unresolved_slo
import caffeine_lang/phase_1/parser/unresolved_team
import caffeine_lang/phase_1/parser/utils/general_common
import glaml_extended
import gleam/dict
import gleam/result
import gleam/string

// ==== Public ====
/// Parses an instantiation from a YAML file. This is a single team with at least one slo.
/// Note that within a configutation repository, there can be multiple instantiations for
/// the same team and even the same service. Logic for this lives within the linking code.
pub fn parse_unresolved_team_instantiation(
  file_path: String,
) -> Result(unresolved_team.Team, String) {
  use params <- result.try(general_common.extract_params_from_file_path(
    file_path,
  ))
  let assert Ok(team_name) = dict.get(params, "team_name")

  use slos <- result.try(parse_slos_instantiation(file_path, params))

  Ok(unresolved_team.Team(name: team_name, slos: slos))
}

pub fn parse_slos_instantiation(
  file_path: String,
  params: dict.Dict(String, String),
) -> Result(List(unresolved_slo.Slo), String) {
  general_common.parse_specification(file_path, params, parse_slo, "slos")
}

// ==== Private ====
/// Parses a single SLO.
fn parse_slo(
  slo: glaml_extended.Node,
  params: dict.Dict(String, String),
) -> Result(unresolved_slo.Slo, String) {
  use name <- result.try(glaml_extended.extract_string_from_node(slo, "name"))
  use sli_type <- result.try(glaml_extended.extract_string_from_node(
    slo,
    "sli_type",
  ))

  // typed_instatiation_of_query_templatized_variables is optional, default to empty dict if missing
  // but still error on type mismatches
  use typed_instatiation_of_query_templatized_variables <- result.try(
    case
      glaml_extended.extract_dict_strings_from_node(
        slo,
        "typed_instatiation_of_query_templatized_variables",
      )
    {
      Ok(dict) -> Ok(dict)
      Error(msg) ->
        case string.starts_with(msg, "Missing") {
          True -> Ok(dict.new())
          False -> Error(msg)
        }
    },
  )

  use threshold <- result.try(glaml_extended.extract_float_from_node(
    slo,
    "threshold",
  ))
  use window_in_days <- result.try(glaml_extended.extract_int_from_node(
    slo,
    "window_in_days",
  ))

  let assert Ok(service_name) = dict.get(params, "service_name")

  Ok(unresolved_slo.Slo(
    name: name,
    sli_type: sli_type,
    typed_instatiation_of_query_templatized_variables: typed_instatiation_of_query_templatized_variables,
    threshold: threshold,
    service_name: service_name,
    window_in_days: window_in_days,
  ))
}
