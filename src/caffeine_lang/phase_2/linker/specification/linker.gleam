import caffeine_lang/phase_1/parser/unresolved_query_template_type
import caffeine_lang/phase_1/parser/unresolved_service
import caffeine_lang/phase_1/parser/unresolved_sli_type
import caffeine_lang/phase_2/linker/basic_type
import caffeine_lang/phase_2/linker/query_template_type
import caffeine_lang/phase_2/linker/service
import caffeine_lang/phase_2/linker/sli_type
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import gleam/dict
import gleam/list
import gleam/result

// ==== Public ====
/// This function is a three step process. While it fundamentally enables us to resolve
/// the specification (services), it also semantically validates that the specification
/// makes sense; right now this just means that we're able to link query_template_types to sli_types,
/// query_template_filters to query_template_types, and sli_types to services.
pub fn link_and_validate_specification_sub_parts(
  services: List(unresolved_service.Service),
  unresolved_sli_types: List(unresolved_sli_type.SliType),
  basic_types: List(basic_type.BasicType),
  query_template_types_unresolved: List(
    unresolved_query_template_type.QueryTemplateType,
  ),
) -> Result(List(service.Service), String) {
  // First we need to resolve query template types by linking filters to them
  use resolved_query_template_types <- result.try(
    query_template_types_unresolved
    |> list.map(fn(query_template_type) {
      resolve_unresolved_query_template_type(query_template_type, basic_types)
    })
    |> result.all,
  )

  // Then we need to link query_template_types to sli_types
  use resolved_sli_types <- result.try(
    unresolved_sli_types
    |> list.map(fn(sli_type) {
      resolve_unresolved_sli_type(
        sli_type,
        resolved_query_template_types,
        basic_types,
      )
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

/// This function takes an unresolved QueryTemplateType and a list of BasicTypes and returns a resolved QueryTemplateType.
pub fn resolve_unresolved_query_template_type(
  unresolved_query_template_type: unresolved_query_template_type.QueryTemplateType,
  basic_types: List(basic_type.BasicType),
) -> Result(query_template_type.QueryTemplateType, String) {
  case unresolved_query_template_type {
    unresolved_query_template_type.QueryTemplateType(
      name,
      metric_attribute_names,
      query,
    ) -> {
      // Find all the basic types that are used in this query template type
      let filters =
        metric_attribute_names
        |> list.map(fn(attribute_name) {
          fetch_by_attribute_name_basic_type(basic_types, attribute_name)
        })
        |> result.all
        |> result.unwrap([])

      Ok(query_template_type.QueryTemplateType(
        name: name,
        specification_of_query_templates: filters,
        query: query,
      ))
    }
  }
}

/// This function takes an unresolved SliType, a list of QueryTemplateTypes, and a list of BasicTypes and returns a resolved SliType.
pub fn resolve_unresolved_sli_type(
  unresolved_sli_type: unresolved_sli_type.SliType,
  query_template_types: List(query_template_type.QueryTemplateType),
  basic_types: List(basic_type.BasicType),
) -> Result(sli_type.SliType, String) {
  // find the query template type
  use query_template_type <- result.try(fetch_by_name_query_template_type(
    query_template_types,
    unresolved_sli_type.query_template_type,
  ))

  // Resolve filter names to actual filter objects
  let specification_of_query_templatized_variables =
    unresolved_sli_type.specification_of_query_templatized_variables
    |> list.map(fn(attribute_name) {
      fetch_by_attribute_name_basic_type(basic_types, attribute_name)
    })
    |> result.all
    |> result.unwrap([])

  // Convert metric_attributes to GenericDictionary
  let type_defs =
    query_template_type.specification_of_query_templates
    |> list.fold(dict.new(), fn(acc, filter) {
      dict.insert(acc, filter.attribute_name, filter.attribute_type)
    })

  // Ensure we have a default type for any attribute not in type_defs
  let default_type = accepted_types.String
  let typed_instatiation_of_query_templates =
    unresolved_sli_type.typed_instatiation_of_query_templates
    |> dict.map_values(fn(_, _) { default_type })

  // Merge with type_defs, giving priority to type_defs
  let merged_type_defs =
    dict.merge(typed_instatiation_of_query_templates, type_defs)

  use metric_attributes <- result.try(generic_dictionary.from_string_dict(
    unresolved_sli_type.typed_instatiation_of_query_templates,
    merged_type_defs,
  ))

  Ok(sli_type.SliType(
    name: unresolved_sli_type.name,
    query_template_type: query_template_type,
    specification_of_query_templatized_variables: specification_of_query_templatized_variables,
    typed_instatiation_of_query_templates: metric_attributes,
  ))
}

/// This function takes an unresolved Service and a list of SliTypes and returns a resolved Service.
pub fn resolve_unresolved_service(
  unresolved_service: unresolved_service.Service,
  sli_types: List(sli_type.SliType),
) -> Result(service.Service, String) {
  // fill in the sli types

  let resolved_sli_types =
    unresolved_service.sli_types
    |> list.map(fn(sli_type_name) {
      fetch_by_name_sli_type(sli_types, sli_type_name)
    })
    |> result.all

  case resolved_sli_types {
    Ok(sli_types) ->
      Ok(service.Service(
        name: unresolved_service.name,
        supported_sli_types: sli_types,
      ))
    Error(_) -> Error("Failed to link sli types to service")
  }
}

// ==== Private ====
/// This function fetches a single SliType by name.
fn fetch_by_name_sli_type(
  values: List(sli_type.SliType),
  name: String,
) -> Result(sli_type.SliType, String) {
  list.find(values, fn(value) { value.name == name })
  |> result.replace_error("SliType " <> name <> " not found")
}

/// This function fetches a single QueryTemplateType by name.
fn fetch_by_name_query_template_type(
  values: List(query_template_type.QueryTemplateType),
  name: String,
) -> Result(query_template_type.QueryTemplateType, String) {
  list.find(values, fn(query_template_type) { query_template_type.name == name })
  |> result.replace_error("QueryTemplateType " <> name <> " not found")
}

/// This function fetches a single BasicType by attribute name.
fn fetch_by_attribute_name_basic_type(
  values: List(basic_type.BasicType),
  attribute_name: String,
) -> Result(basic_type.BasicType, String) {
  case
    list.find(values, fn(basic_type) {
      basic_type.attribute_name == attribute_name
    })
  {
    Ok(basic_type) -> Ok(basic_type)
    Error(_) -> Error("BasicType " <> attribute_name <> " not found")
  }
}
