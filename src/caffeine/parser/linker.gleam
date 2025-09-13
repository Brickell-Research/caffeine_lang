import caffeine/intermediate_representation
import caffeine/parser/specification
import gleam/list
import gleam/result

/// This function is a two step process. While it fundamentally enables us to sugar
/// the specification (services), it also semantically validates that the specification
/// makes sense; right now this just means that we're able to link sli_types to services
/// and sli_filters to sli_types.
pub fn link_and_validate_specification_sub_parts(
  services: List(specification.ServicePreSugared),
  sli_types: List(specification.SliTypePreSugared),
  sli_filters: List(intermediate_representation.SliFilter),
) -> Result(List(intermediate_representation.Service), String) {
  // First we need to link sli_filters to sli_types
  use sugared_sli_types <- result.try(
    sli_types
    |> list.map(fn(sli_type) {
      sugar_pre_sugared_sli_type(sli_type, sli_filters)
    })
    |> result.all,
  )

  // Next we need to link sli_types to services
  use sugared_services <- result.try(
    services
    |> list.map(fn(service) {
      sugar_pre_sugared_service(service, sugared_sli_types)
    })
    |> result.all,
  )

  Ok(sugared_services)
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

/// This function takes a pre sugared SliType and a list of SliFilters and returns a sugared SliType.
pub fn sugar_pre_sugared_sli_type(
  pre_sugared_sli_type: specification.SliTypePreSugared,
  sli_filters: List(intermediate_representation.SliFilter),
) -> Result(intermediate_representation.SliType, String) {
  // fill in the sli filters

  let sugared_filters =
    pre_sugared_sli_type.filters
    |> list.map(fn(filter_name) {
      fetch_by_attribute_name_sli_filter(sli_filters, filter_name)
    })
    |> result.all

  case sugared_filters {
    Ok(filters) ->
      Ok(intermediate_representation.SliType(
        name: pre_sugared_sli_type.name,
        filters: filters,
        query_template: pre_sugared_sli_type.query_template,
      ))
    Error(_) -> Error("Failed to link sli filters to sli type")
  }
}

/// This function takes a pre sugared Service and a list of SliTypes and returns a sugared Service.
pub fn sugar_pre_sugared_service(
  pre_sugared_service: specification.ServicePreSugared,
  sli_types: List(intermediate_representation.SliType),
) -> Result(intermediate_representation.Service, String) {
  // fill in the sli types

  let sugared_sli_types =
    pre_sugared_service.sli_types
    |> list.map(fn(sli_type_name) {
      fetch_by_name_sli_type(sli_types, sli_type_name)
    })
    |> result.all

  case sugared_sli_types {
    Ok(sli_types) ->
      Ok(intermediate_representation.Service(
        name: pre_sugared_service.name,
        supported_sli_types: sli_types,
      ))
    Error(_) -> Error("Failed to link sli types to service")
  }
}
