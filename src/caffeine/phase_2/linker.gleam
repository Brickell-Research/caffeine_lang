import caffeine/phase_1/parser/instantiation
import caffeine/phase_1/parser/specification.{
  parse_services_specification, parse_sli_filters_specification,
  parse_sli_types_specification,
}
import caffeine/types/intermediate_representation

import caffeine/types/specification_types.{
  type ServiceUnresolved, type SliTypeUnresolved,
}

import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

/// This function is a two step process. While it fundamentally enables us to resolve
/// the specification (services), it also semantically validates that the specification
/// makes sense; right now this just means that we're able to link sli_types to services
/// and sli_filters to sli_types.
pub fn link_and_validate_specification_sub_parts(
  services: List(ServiceUnresolved),
  sli_types: List(SliTypeUnresolved),
  sli_filters: List(intermediate_representation.SliFilter),
) -> Result(List(intermediate_representation.Service), String) {
  // First we need to link sli_filters to sli_types
  use resolved_sli_types <- result.try(
    sli_types
    |> list.map(fn(sli_type) {
      resolve_unresolved_sli_type(sli_type, sli_filters)
    })
    |> result.all,
  )

  // Next we need to link sli_types to services
  use resolved_services <- result.try(
    services
    |> list.map(fn(service) {
      resolve_unresolved_service(service, resolved_sli_types)
    })
    |> result.all,
  )

  Ok(resolved_services)
}

/// This function fetches a single SliFilter by attribute name.
pub fn fetch_by_attribute_name_sli_filter(
  values: List(intermediate_representation.SliFilter),
  attribute_name: String,
) -> Result(intermediate_representation.SliFilter, String) {
  list.find(values, fn(value) { value.attribute_name == attribute_name })
  |> result.replace_error("Attribute " <> attribute_name <> " not found")
}

/// This function fetches a single SliType by name.
pub fn fetch_by_name_sli_type(
  values: List(intermediate_representation.SliType),
  name: String,
) -> Result(intermediate_representation.SliType, String) {
  list.find(values, fn(value) { value.name == name })
  |> result.replace_error("SliType " <> name <> " not found")
}

/// This function takes an unresolved SliType and a list of SliFilters and returns a resolved SliType.
pub fn resolve_unresolved_sli_type(
  unresolved_sli_type: SliTypeUnresolved,
  sli_filters: List(intermediate_representation.SliFilter),
) -> Result(intermediate_representation.SliType, String) {
  // fill in the sli filters

  let resolved_filters =
    unresolved_sli_type.filters
    |> list.map(fn(filter_name) {
      fetch_by_attribute_name_sli_filter(sli_filters, filter_name)
    })
    |> result.all

  case resolved_filters {
    Ok(filters) ->
      Ok(intermediate_representation.SliType(
        name: unresolved_sli_type.name,
        filters: filters,
        query_template: unresolved_sli_type.query_template,
      ))
    Error(_) -> Error("Failed to link sli filters to sli type")
  }
}

/// This function takes an unresolved Service and a list of SliTypes and returns a resolved Service.
pub fn resolve_unresolved_service(
  unresolved_service: ServiceUnresolved,
  sli_types: List(intermediate_representation.SliType),
) -> Result(intermediate_representation.Service, String) {
  // fill in the sli types

  let resolved_sli_types =
    unresolved_service.sli_types
    |> list.map(fn(sli_type_name) {
      fetch_by_name_sli_type(sli_types, sli_type_name)
    })
    |> result.all

  case resolved_sli_types {
    Ok(sli_types) ->
      Ok(intermediate_representation.Service(
        name: unresolved_service.name,
        supported_sli_types: sli_types,
      ))
    Error(_) -> Error("Failed to link sli types to service")
  }
}

/// Given a list of teams which map to single service SLOs, we want to aggregate all SLOs for a single team
/// into a single team object.
pub fn aggregate_teams_and_slos(
  teams: List(intermediate_representation.Team),
) -> List(intermediate_representation.Team) {
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
      intermediate_representation.Team(name: team_name, slos: all_slos)

    [aggregated_team, ..acc]
  })
}

pub fn link_specification_and_instantiation(
  specification_directory: String,
  instantiations_directory: String,
) -> Result(intermediate_representation.Organization, String) {
  // ==== Specification ====
  use unresolved_services <- result.try(parse_services_specification(
    specification_directory <> "/services.yaml",
  ))

  use unresolved_sli_types <- result.try(parse_sli_types_specification(
    specification_directory <> "/sli_types.yaml",
  ))

  use sli_filters <- result.try(parse_sli_filters_specification(
    specification_directory <> "/sli_filters.yaml",
  ))

  use linked_services <- result.try(link_and_validate_specification_sub_parts(
    unresolved_services,
    unresolved_sli_types,
    sli_filters,
  ))

  // ==== Instantiations ====
  use instantiations_files <- result.try(get_instantiation_yaml_files(
    instantiations_directory,
  ))

  use instantiations <- result.try(
    instantiations_files
    |> list.try_map(fn(file) { instantiation.parse_instantiation(file) }),
  )

  Ok(intermediate_representation.Organization(
    service_definitions: linked_services,
    teams: instantiations,
  ))
}

pub fn get_instantiation_yaml_files(
  base_directory: String,
) -> Result(List(String), String) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
}

fn read_directory_or_error(
  directory_path: String,
) -> Result(List(String), String) {
  case simplifile.read_directory(directory_path) {
    Ok(items) -> Ok(items)
    Error(_) -> Error("Failed to read directory: " <> directory_path)
  }
}

fn process_top_level_item(
  base_directory: String,
  item_name: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  let item_path = base_directory <> "/" <> item_name

  case is_directory(item_path), string.ends_with(item_name, "specifications") {
    True, False ->
      collect_yaml_files_from_subdirectory(item_path, accumulated_files)
    True, True -> Ok(accumulated_files)
    // Skip other directories
    False, _ -> Ok(accumulated_files)
    // Skip files at the top level
  }
}

fn is_directory(path: String) -> Bool {
  case simplifile.is_directory(path) {
    Ok(True) -> True
    _ -> False
  }
}

fn collect_yaml_files_from_subdirectory(
  subdirectory_path: String,
  accumulated_files: List(String),
) -> Result(List(String), String) {
  use files_in_subdirectory <- result.try(read_directory_or_error(
    subdirectory_path,
  ))

  let yaml_files =
    extract_yaml_files_with_full_paths(files_in_subdirectory, subdirectory_path)

  Ok(list.append(accumulated_files, yaml_files))
}

fn extract_yaml_files_with_full_paths(
  files: List(String),
  directory_path: String,
) -> List(String) {
  files
  |> list.filter(fn(file) { string.ends_with(file, ".yaml") })
  |> list.map(fn(file) { directory_path <> "/" <> file })
}
