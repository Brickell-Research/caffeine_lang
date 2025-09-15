import caffeine/phase_2/linker/instantiation/linker
import caffeine/types/intermediate_representation.{Slo, Team}
import gleam/dict
import gleam/list
import gleam/string

pub fn aggregate_teams_and_slos_test() {
  let slo_a =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.9,
      sli_type: "sli_type_a",
      service_name: "service_a",
      window_in_days: 30,
    )

  let slo_b =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.8,
      sli_type: "sli_type_b",
      service_name: "service_b",
      window_in_days: 30,
    )

  let slo_c =
    Slo(
      filters: dict.from_list([#("key", "value")]),
      threshold: 0.7,
      sli_type: "sli_type_c",
      service_name: "service_c",
      window_in_days: 30,
    )

  let team_a_service_a = Team(name: "team_a", slos: [slo_a])
  let team_a_service_b = Team(name: "team_a", slos: [slo_b])
  let team_b_service_c = Team(name: "team_b", slos: [slo_c])

  let teams = [team_a_service_a, team_a_service_b, team_b_service_c]

  let actual = linker.aggregate_teams_and_slos(teams)

  let expected = [
    Team(name: "team_a", slos: [slo_b, slo_a]),
    Team(name: "team_b", slos: [slo_c]),
  ]

  assert list.sort(actual, fn(a, b) { string.compare(a.name, b.name) })
    == list.sort(expected, fn(a, b) { string.compare(a.name, b.name) })
}
