import caffeine_lang/phase_2/linker/query_template_type
import caffeine_query_language/parser
import gleam/dict

/// An SLI intance with all the aggregated information from previous steps.
///
/// Example:
/// ```
/// Sli(
///   query_template_type: "good_over_bad",
///   metric_attributes: {
///     numerator_query: "max:latency(<100ms, {service="super_scalabale_web_service",requests_valid=true})",
///     denominator_query: "max:latency(<100ms, {service="super_scalabale_web_service"})",
///   },
///   resolved_query: ExpContainer(...)
/// )
/// ```
pub type Sli {
  Sli(
    name: String,
    query_template_type: query_template_type.QueryTemplateType,
    metric_attributes: dict.Dict(String, String),
    resolved_query: parser.ExpContainer,
  )
}
