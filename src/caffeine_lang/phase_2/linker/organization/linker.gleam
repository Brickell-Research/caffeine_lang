import caffeine_lang/phase_1/parser/instantiation/unresolved_team_instantiation
import caffeine_lang/phase_1/parser/specification/basic_types_specification
import caffeine_lang/phase_1/parser/specification/unresolved_query_template_specification
import caffeine_lang/phase_1/parser/specification/unresolved_services_specification
import caffeine_lang/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine_lang/phase_2/linker/instantiation/linker as instantiation_linker
import caffeine_lang/phase_2/linker/specification/linker as specification_linker
import caffeine_lang/types/ast/organization
import gleam/list
import gleam/result
import gleam/string
import simplifile

// ==== Public ====
/// This function links the specification and instantiations into a single Organization.
pub fn link_specification_and_instantiation(
  specification_directory: String,
  instantiations_directory: String,
) -> Result(organization.Organization, String) {
  // ==== Specification ====
  use unresolved_services <- result.try(
    unresolved_services_specification.parse_unresolved_services_specification(
      specification_directory <> "/services.yaml",
    ),
  )

  use unresolved_sli_types <- result.try(
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      specification_directory <> "/sli_types.yaml",
    ),
  )

  use basic_types <- result.try(
    basic_types_specification.parse_basic_types_specification(
      specification_directory <> "/basic_types.yaml",
    ),
  )

  use query_template_types_unresolved <- result.try(
    unresolved_query_template_specification.parse_unresolved_query_template_types_specification(
      specification_directory <> "/query_template_types.yaml",
    ),
  )

  use linked_services <- result.try(
    specification_linker.link_and_validate_specification_sub_parts(
      unresolved_services,
      unresolved_sli_types,
      basic_types,
      query_template_types_unresolved,
    ),
  )

  // ==== Instantiations ====
  use instantiations_files <- result.try(get_instantiation_yaml_files(
    instantiations_directory,
  ))

  use instantiations <- result.try(
    instantiations_files
    |> list.try_map(fn(file) {
      unresolved_team_instantiation.parse_unresolved_team_instantiation(file)
    }),
  )

  use linked_teams <- result.try(
    instantiations
    |> list.try_map(fn(instantiation) {
      instantiation_linker.link_and_validate_instantiation(
        instantiation,
        linked_services,
      )
    }),
  )

  Ok(organization.Organization(
    service_definitions: linked_services,
    teams: linked_teams,
  ))
}

/// This function returns a list of all YAML files in the given directory.
pub fn get_instantiation_yaml_files(
  base_directory: String,
) -> Result(List(String), String) {
  use top_level_items <- result.try(read_directory_or_error(base_directory))

  top_level_items
  |> list.try_fold([], fn(accumulated_files, item_name) {
    process_top_level_item(base_directory, item_name, accumulated_files)
  })
}

// ==== Private ====
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
