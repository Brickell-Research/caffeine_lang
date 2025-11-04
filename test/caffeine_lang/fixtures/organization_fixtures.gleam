import caffeine_lang/types/ast/basic_type
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/query_template_type
import caffeine_lang/types/ast/service
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/team
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import cql/parser.{ExpContainer, Primary, PrimaryWord, Word}
import gleam/dict
import gleam/result

/// Creates a basic empty organization
pub fn empty_organization() -> organization.Organization {
  organization.Organization(teams: [], service_definitions: [])
}

/// Creates an organization with given teams and services
pub fn organization_with_teams_and_services(
  teams: List(team.Team),
  services: List(service.Service),
) -> organization.Organization {
  organization.Organization(teams: teams, service_definitions: services)
}

/// Creates a basic query template type for testing
pub fn basic_query_template_type() -> query_template_type.QueryTemplateType {
  query_template_type.QueryTemplateType(
    specification_of_query_templates: [],
    name: "good_over_bad",
    query: ExpContainer(Primary(PrimaryWord(Word("")))),
  )
}

/// Creates a basic SLI type for testing
pub fn basic_sli_type(name: String) -> sli_type.SliType {
  let metric_attrs =
    generic_dictionary.from_string_dict(
      dict.from_list([#("numerator_query", ""), #("denominator_query", "")]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  sli_type.SliType(
    name: name,
    query_template_type: basic_query_template_type(),
    typed_instatiation_of_query_templates: metric_attrs,
    specification_of_query_templatized_variables: [],
  )
}

/// Creates a basic service with a given name and SLI types
pub fn basic_service(
  name: String,
  sli_types: List(sli_type.SliType),
) -> service.Service {
  service.Service(name: name, supported_sli_types: sli_types)
}

/// Creates a service with a single basic SLI type
pub fn service_with_basic_sli_type(
  service_name: String,
  sli_type_name: String,
) -> service.Service {
  service.Service(name: service_name, supported_sli_types: [
    basic_sli_type(sli_type_name),
  ])
}

/// Creates a basic type definition
pub fn basic_type_def(
  name: String,
  attr_type: accepted_types.AcceptedTypes,
) -> basic_type.BasicType {
  basic_type.BasicType(attribute_name: name, attribute_type: attr_type)
}
