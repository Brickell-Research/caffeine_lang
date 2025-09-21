import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/slo
import caffeine_lang/types/ast/sli_type 
import caffeine_lang/phase_4/resolved/types as resolved_types
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

pub fn resolve_slos(
  organization: organization.Organization,
) -> Result(List(resolved_types.ResolvedSlo), String) {
  let sli_types =
    organization.service_definitions
    |> list.flat_map(fn(service_definition) {
      service_definition.supported_sli_types
    })
    |> list.unique

  organization.teams
  |> list.map(fn(team) {
    team.slos
    |> list.map(fn(slo) { resolve_slo(slo, team.name, sli_types) })
    |> result.all
  })
  |> result.all
  |> result.map(list.flatten)
}

pub fn resolve_slo(
  slo: slo.Slo,
  team_name: String,
  sli_types: List(sli_type.SliType),
) -> Result(resolved_types.ResolvedSlo, String) {
  let assert Ok(sli_type) =
    sli_types
    |> list.find(fn(sli_type) { sli_type.name == slo.sli_type })

  // Convert typed instantiation to Dict(String, String)
  let filters_dict =
    generic_dictionary.to_string_dict(
      slo.typed_instatiation_of_query_templatized_variables,
    )

  use resolve_sli <- result.try(resolve_sli(filters_dict, sli_type))

  Ok(resolved_types.ResolvedSlo(
    window_in_days: slo.window_in_days,
    threshold: slo.threshold,
    service_name: slo.service_name,
    team_name: team_name,
    sli: resolve_sli,
  ))
}

pub fn resolve_sli(
  filters: dict.Dict(String, String),
  sli_type: sli_type.SliType,
) -> Result(resolved_types.ResolvedSli, String) {
  let resolved_queries =
    sli_type.typed_instatiation_of_query_templates
    |> generic_dictionary.to_string_dict
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(metric_attribute, template) = pair
      let filter_names = dict.keys(filters)

      list.fold(filter_names, template, fn(acc, name) {
        case dict.get(filters, name) {
          Ok(value) -> string.replace(acc, "$$" <> name <> "$$", value)
          Error(_) -> acc
        }
      })
      |> fn(processed) { #(metric_attribute, processed) }
    })
    |> dict.from_list

  Ok(resolved_types.ResolvedSli(
    query_template_type: sli_type.query_template_type,
    metric_attributes: resolved_queries,
  ))
}
