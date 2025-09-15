import caffeine/types/intermediate_representation
import caffeine/types/specification_types.{
  type QueryTemplateTypeUnresolved, type ServiceUnresolved,
  type SliTypeUnresolved, QueryTemplateTypeUnresolved,
}
import gleam/list
import gleam/result

// ==== Public ====
/// This function is a three step process. While it fundamentally enables us to resolve
/// the specification (services), it also semantically validates that the specification
/// makes sense; right now this just means that we're able to link query_template_types to sli_types,
/// query_template_filters to query_template_types, and sli_types to services.
pub fn link_and_validate_specification_sub_parts(
  services: List(ServiceUnresolved),
  sli_types: List(SliTypeUnresolved),
  query_template_filters: List(intermediate_representation.QueryTemplateFilter),
  query_template_types_unresolved: List(QueryTemplateTypeUnresolved),
) -> Result(List(intermediate_representation.Service), String) {
  // First we need to resolve query template types by linking filters to them
  use resolved_query_template_types <- result.try(
    query_template_types_unresolved
    |> list.map(fn(query_template_type) {
      resolve_unresolved_query_template_type(
        query_template_type,
        query_template_filters,
      )
    })
    |> result.all,
  )

  // Then we need to link query_template_types to sli_types
  use resolved_sli_types <- result.try(
    sli_types
    |> list.map(fn(sli_type) {
      resolve_unresolved_sli_type(sli_type, resolved_query_template_types, query_template_filters)
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

/// This function takes an unresolved QueryTemplateType and a list of QueryTemplateFilters and returns a resolved QueryTemplateType.
pub fn resolve_unresolved_query_template_type(
  unresolved_query_template_type: QueryTemplateTypeUnresolved,
  query_template_filters: List(intermediate_representation.QueryTemplateFilter),
) -> Result(intermediate_representation.QueryTemplateType, String) {
  case unresolved_query_template_type {
    QueryTemplateTypeUnresolved(name, metric_attribute_names) -> {
      // Resolve the metric attribute names to actual filters
      let resolved_metric_attributes =
        metric_attribute_names
        |> list.map(fn(attribute_name) {
          fetch_by_attribute_name_query_template_filter(
            query_template_filters,
            attribute_name,
          )
        })
        |> result.all

      case resolved_metric_attributes {
        Ok(metric_attributes) ->
          Ok(intermediate_representation.QueryTemplateType(
            name: name,
            metric_attributes: metric_attributes,
          ))
        Error(error) -> Error(error)
      }
    }
  }
}

/// This function takes an unresolved SliType, a list of QueryTemplateTypes, and a list of QueryTemplateFilters and returns a resolved SliType.
pub fn resolve_unresolved_sli_type(
  unresolved_sli_type: SliTypeUnresolved,
  query_template_types: List(intermediate_representation.QueryTemplateType),
  query_template_filters: List(intermediate_representation.QueryTemplateFilter),
) -> Result(intermediate_representation.SliType, String) {
  // find the query template type
  use query_template_type <- result.try(fetch_by_name_query_template_type(
    query_template_types,
    unresolved_sli_type.query_template_type,
  ))

  // Resolve filter names to actual filter objects
  use resolved_filters <- result.try(
    unresolved_sli_type.filters
    |> list.map(fn(filter_name) {
      fetch_by_attribute_name_query_template_filter(
        query_template_filters,
        filter_name,
      )
    })
    |> result.all,
  )

  Ok(intermediate_representation.SliType(
    name: unresolved_sli_type.name,
    query_template_type: query_template_type,
    metric_attributes: unresolved_sli_type.metric_attributes,
    filters: resolved_filters,
  ))
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

// ==== Private ====
/// This function fetches a single SliType by name.
fn fetch_by_name_sli_type(
  values: List(intermediate_representation.SliType),
  name: String,
) -> Result(intermediate_representation.SliType, String) {
  list.find(values, fn(value) { value.name == name })
  |> result.replace_error("SliType " <> name <> " not found")
}

/// This function fetches a single QueryTemplateType by name.
fn fetch_by_name_query_template_type(
  values: List(intermediate_representation.QueryTemplateType),
  name: String,
) -> Result(intermediate_representation.QueryTemplateType, String) {
  list.find(values, fn(query_template_type) { query_template_type.name == name })
  |> result.replace_error("QueryTemplateType " <> name <> " not found")
}

/// This function fetches a single QueryTemplateFilter by attribute name.
fn fetch_by_attribute_name_query_template_filter(
  values: List(intermediate_representation.QueryTemplateFilter),
  attribute_name: String,
) -> Result(intermediate_representation.QueryTemplateFilter, String) {
  case
    list.find(values, fn(filter) { filter.attribute_name == attribute_name })
  {
    Ok(filter) -> Ok(filter)
    Error(_) -> Error("QueryTemplateFilter " <> attribute_name <> " not found")
  }
}
