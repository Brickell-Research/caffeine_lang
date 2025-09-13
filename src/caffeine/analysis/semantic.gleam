//// We perform the following semantic analysis against the intermediate representation of the organization.
//// (3) Ensure that all SLOs are referencing valid SLI types for their service.
//// (5) Ensure that all filters are valid for the SLI type.
//// (7) Ensure no duplicate service names or duplicate SLOs for a single service and team combination.
//// (8) Ensure that all services, sli types, and sli filters in the specification are unique.
//// (9) Ensure that all filters within the SLOs are the correct types for the SLI type's filters.
//// (10) For every required true sli filter, ensure that it is present in the SLO.
//// (11) For every filter within SLO instantiation, if unknown, reject it.
//// (12) Perform query template hygiene:
////    (12.1) Ensure that the query template is valid and not empty.
////    (12.2) Every template variable in the query template must be present in the filters of the SLI type.
//// (13) Warn on unused sli types, sli filters, and services.
//// (14) Normalize team names, service names, sli type names, sli filter names, and sli filter attribute names to lowercase.

import caffeine/intermediate_representation.{type Organization, type Slo}
import gleam/list

pub type SemanticAnalysisError {
  UndefinedServiceError(service_names: List(String))
  UndefinedSliTypeError(sli_type_names: List(String))
  InvalidSloThresholdError(thresholds: List(Float))
  DuplicateServiceError(service_names: List(String))
}

fn slos_filtered_attribute(
  organization: Organization,
  extract_fn: fn(Slo) -> a,
  predicate_fn: fn(a) -> Bool,
) -> List(a) {
  organization.teams
  |> list.flat_map(fn(team) { team.slos })
  |> list.map(extract_fn)
  |> list.filter(predicate_fn)
  |> list.unique()
}

pub fn validate_services_from_instantiation(
  organization: Organization,
) -> Result(Bool, SemanticAnalysisError) {
  let defined_services =
    organization.service_definitions
    |> list.map(fn(service_definition) { service_definition.name })

  let undefined_services =
    slos_filtered_attribute(
      organization,
      fn(slo) { slo.service_name },
      fn(service_name) { !list.contains(defined_services, service_name) },
    )

  case undefined_services {
    [] -> Ok(True)
    services -> Error(UndefinedServiceError(service_names: services))
  }
}

// TODO: fix this - it is incorrect as an sli type is tied to a service.
pub fn validate_sli_types_exist_from_instantiation(
  organization: Organization,
) -> Result(Bool, SemanticAnalysisError) {
  let defined_sli_types =
    organization.service_definitions
    |> list.map(fn(service_definition) {
      service_definition.supported_sli_types
    })
    |> list.flat_map(fn(sli_types) { sli_types })
    |> list.map(fn(sli_type) { sli_type.name })
    |> list.unique()

  let undefined_sli_types =
    slos_filtered_attribute(
      organization,
      fn(slo) { slo.sli_type },
      fn(sli_type_name) { !list.contains(defined_sli_types, sli_type_name) },
    )

  case undefined_sli_types {
    [] -> Ok(True)
    sli_types -> Error(UndefinedSliTypeError(sli_type_names: sli_types))
  }
}

/// Ensure that all SLO thresholds are between 0 and 100.
pub fn validate_slos_thresholds_reasonable_from_instantiation(
  organization: Organization,
) -> Result(Bool, SemanticAnalysisError) {
  let invalid_thresholds =
    slos_filtered_attribute(
      organization,
      fn(slo) { slo.threshold },
      fn(threshold) { threshold <. 0.0 || threshold >. 100.0 },
    )

  case invalid_thresholds {
    [] -> Ok(True)
    thresholds -> Error(InvalidSloThresholdError(thresholds: thresholds))
  }
}

pub fn perform_semantic_analysis(
  organization: Organization,
) -> Result(Bool, SemanticAnalysisError) {
  case validate_services_from_instantiation(organization) {
    Ok(_) -> {
      case validate_sli_types_exist_from_instantiation(organization) {
        Ok(_) -> {
          case
            validate_slos_thresholds_reasonable_from_instantiation(organization)
          {
            Ok(_) -> Ok(True)
            Error(error) -> Error(error)
          }
        }
        Error(error) -> Error(error)
      }
    }
    Error(error) -> Error(error)
  }
}
