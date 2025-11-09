import caffeine_lang/phase_2/linker/slo
import caffeine_lang/phase_2/linker/team
import caffeine_lang/types/generic_dictionary

/// Creates a basic team for testing with default values
pub fn basic_team() -> team.Team {
  team.Team(name: "test_team", slos: [])
}

/// Creates a team with a given name
pub fn team_with_name(name: String) -> team.Team {
  team.Team(name: name, slos: [])
}

/// Creates a team with a single SLO
pub fn team_with_slo(name: String, slo: slo.Slo) -> team.Team {
  team.Team(name: name, slos: [slo])
}

/// Creates a team with multiple SLOs
pub fn team_with_slos(name: String, slos: List(slo.Slo)) -> team.Team {
  team.Team(name: name, slos: slos)
}

/// Creates a team with a basic availability SLO
pub fn team_with_availability_slo(
  team_name: String,
  service_name: String,
) -> team.Team {
  team.Team(name: team_name, slos: [
    slo.Slo(
      name: team_name <> "_" <> service_name <> "_availability",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: service_name,
      window_in_days: 30,
    ),
  ])
}

/// Creates team1 with two availability SLOs for semantic tests
pub fn team_1() -> team.Team {
  team.Team(name: "team1", slos: [
    slo.Slo(
      name: "team1_slo_1",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team1",
      window_in_days: 30,
    ),
    slo.Slo(
      name: "team1_slo_2",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
      threshold: 99.9,
      sli_type: "availability",
      service_name: "team2",
      window_in_days: 30,
    ),
  ])
}
