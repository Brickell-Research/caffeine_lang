import caffeine/types/ast
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

// ==== Public ====
/// Given a list of teams which map to single service SLOs, we want to aggregate all SLOs for a single team
/// into a single team object.
pub fn aggregate_teams_and_slos(
  teams: List(ast.Team),
) -> List(ast.Team) {
  let dict_of_teams =
    list.fold(teams, dict.new(), fn(acc, team) {
      dict.upsert(acc, team.name, fn(existing_teams) {
        case existing_teams {
          Some(teams_list) -> [team, ..teams_list]
          None -> [team]
        }
      })
    })

  dict.fold(dict_of_teams, [], fn(acc, team_name, teams_list) {
    let all_slos =
      teams_list
      |> list.map(fn(team) { team.slos })
      |> list.flatten

    let aggregated_team =
      ast.Team(name: team_name, slos: all_slos)

    [aggregated_team, ..acc]
  })
}
