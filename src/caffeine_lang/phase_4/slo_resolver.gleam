import caffeine_lang/types/ast.{type Organization, type SliType, type Slo}
import caffeine_lang/types/intermediate_representation.{
  type ResolvedSli, type ResolvedSlo, ResolvedSli, ResolvedSlo,
}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub fn resolve_slos(
  organization: Organization,
) -> Result(List(ResolvedSlo), String) {
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
  slo: Slo,
  team_name: String,
  sli_types: List(SliType),
) -> Result(ResolvedSlo, String) {
  let assert Ok(sli_type) =
    sli_types
    |> list.find(fn(sli_type) { sli_type.name == slo.sli_type })

  use resolve_sli <- result.try(resolve_sli(slo.filters, sli_type))

  Ok(ResolvedSlo(
    window_in_days: slo.window_in_days,
    threshold: slo.threshold,
    service_name: slo.service_name,
    team_name: team_name,
    sli: resolve_sli,
  ))
}

pub fn resolve_sli(
  filters: Dict(String, String),
  sli_type: SliType,
) -> Result(ResolvedSli, String) {
  let resolved_queries =
    sli_type.metric_attributes
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

  Ok(ResolvedSli(
    query_template_type: sli_type.query_template_type,
    metric_attributes: resolved_queries,
  ))
}
