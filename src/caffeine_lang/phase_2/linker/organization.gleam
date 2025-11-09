import caffeine_lang/phase_2/linker/service
import caffeine_lang/phase_2/linker/team

/// An organization represents the union of instantiations and specifications.
pub type Organization {
  Organization(
    teams: List(team.Team),
    service_definitions: List(service.Service),
  )
}
