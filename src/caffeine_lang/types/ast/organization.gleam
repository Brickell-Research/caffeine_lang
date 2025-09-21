import caffeine_lang/types/ast/team
import caffeine_lang/types/ast/service

/// An organization represents the union of instantiations and specifications.
pub type Organization {
  Organization(teams: List(team.Team), service_definitions: List(service.Service))
}
