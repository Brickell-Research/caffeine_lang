import caffeine_lang/common_types/generic_dictionary
import caffeine_lang/phase_1/types as unresolved_types
import caffeine_lang/phase_2/types as ast_types
import gleam/dict
import gleam/list
import gleam/option
import gleam/result

// ==== Public ====
/// Given a list of teams which map to single service SLOs, we want to aggregate all SLOs for a single team
/// into a single team object.
pub fn aggregate_teams_and_slos(
  teams: List(ast_types.Team),
) -> List(ast_types.Team) {
  let dict_of_teams =
    list.fold(teams, dict.new(), fn(acc, team) {
      dict.upsert(acc, team.name, fn(existing_teams) {
        case existing_teams {
          option.Some(teams_list) -> [team, ..teams_list]
          option.None -> [team]
        }
      })
    })

  dict.fold(dict_of_teams, [], fn(acc, team_name, teams_list) {
    let all_slos =
      teams_list
      |> list.map(fn(team) { team.slos })
      |> list.flatten

    let aggregated_team = ast_types.Team(name: team_name, slos: all_slos)

    [aggregated_team, ..acc]
  })
}

pub fn link_and_validate_instantiation(
  unresolved_team: unresolved_types.UnresolvedTeam,
  services: List(ast_types.Service),
) -> Result(ast_types.Team, String) {
  let resolved_slos =
    unresolved_team.slos
    |> list.map(fn(unresolved_slo) { resolve_slo(unresolved_slo, services) })
    |> result.all

  resolved_slos
  |> result.map(fn(slos) {
    ast_types.Team(name: unresolved_team.name, slos: slos)
  })
}

pub fn resolve_slo(
  unresolved_slo: unresolved_types.UnresolvedSlo,
  services: List(ast_types.Service),
) -> Result(ast_types.Slo, String) {
  use service <- result.try(
    list.find(services, fn(s) { s.name == unresolved_slo.service_name })
    |> result.replace_error(
      "Service not found: " <> unresolved_slo.service_name,
    ),
  )

  use sli_type <- result.try(
    list.find(service.supported_sli_types, fn(t) {
      t.name == unresolved_slo.sli_type
    })
    |> result.replace_error("SLI type not found: " <> unresolved_slo.sli_type),
  )

  use typed_instatiation_of_query_templatized_variables <- result.try(
    resolve_filters(
      unresolved_slo.typed_instatiation_of_query_templatized_variables,
      sli_type.specification_of_query_templatized_variables,
    ),
  )

  Ok(ast_types.Slo(
    typed_instatiation_of_query_templatized_variables: typed_instatiation_of_query_templatized_variables,
    threshold: unresolved_slo.threshold,
    sli_type: sli_type.name,
    service_name: unresolved_slo.service_name,
    window_in_days: unresolved_slo.window_in_days,
  ))
}

pub fn resolve_filters(
  unresolved_instantiated_filters: dict.Dict(String, String),
  specification_filters: List(ast_types.BasicType),
) -> Result(generic_dictionary.GenericDictionary, String) {
  let result_entries =
    unresolved_instantiated_filters
    |> dict.keys
    |> list.try_map(fn(key) {
      case
        specification_filters
        |> list.find(fn(filter) { filter.attribute_name == key })
      {
        Ok(spec_type) -> {
          case dict.get(unresolved_instantiated_filters, key) {
            Ok(value) -> {
              let typed_value =
                generic_dictionary.TypedValue(
                  value: value,
                  type_def: spec_type.attribute_type,
                )
              Ok(#(key, typed_value))
            }
            Error(_) -> Error("Value not found for key: " <> key)
          }
        }
        Error(_) -> Error("Filter not found in specification: " <> key)
      }
    })

  result_entries
  |> result.map(dict.from_list)
  |> result.map(generic_dictionary.GenericDictionary)
}
