import caffeine_lang/phase_2/linker/slo
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import gleam/dict

/// Creates a basic SLO for testing with default values
pub fn basic_slo() -> slo.Slo {
  slo.Slo(
    name: "basic_slo",
    typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
    threshold: 99.9,
    sli_type: "availability",
    service_name: "test_service",
    window_in_days: 30,
  )
}

/// Creates an SLO with custom threshold
pub fn slo_with_threshold(threshold: Float) -> slo.Slo {
  slo.Slo(
    name: "threshold_slo",
    typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
    threshold: threshold,
    sli_type: "availability",
    service_name: "test_service",
    window_in_days: 30,
  )
}

/// Creates an SLO with custom service name and SLI type
pub fn slo_with_service_and_type(
  service_name: String,
  sli_type: String,
) -> slo.Slo {
  slo.Slo(
    name: service_name <> "_" <> sli_type,
    typed_instatiation_of_query_templatized_variables: generic_dictionary.new(),
    threshold: 99.9,
    sli_type: sli_type,
    service_name: service_name,
    window_in_days: 30,
  )
}

/// Creates an SLO with custom filters
pub fn slo_with_filters(
  filters: dict.Dict(String, String),
  service_name: String,
  sli_type: String,
) -> slo.Slo {
  let type_map = dict.map_values(filters, fn(_, _) { accepted_types.String })

  let typed_filters = case
    generic_dictionary.from_string_dict(filters, type_map)
  {
    Ok(gd) -> gd
    Error(_) -> generic_dictionary.new()
  }

  slo.Slo(
    name: service_name <> "_" <> sli_type,
    typed_instatiation_of_query_templatized_variables: typed_filters,
    threshold: 99.9,
    sli_type: sli_type,
    service_name: service_name,
    window_in_days: 30,
  )
}
