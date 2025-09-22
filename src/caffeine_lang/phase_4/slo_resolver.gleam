import caffeine_lang/cql/parser
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/resolved/resolved_sli
import caffeine_lang/types/resolved/resolved_slo
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

pub fn resolve_slos(
  organization: organization.Organization,
) -> Result(List(resolved_slo.Slo), String) {
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
) -> Result(resolved_slo.Slo, String) {
  let assert Ok(sli_type) =
    sli_types
    |> list.find(fn(sli_type) { sli_type.name == slo.sli_type })

  // Convert typed instantiation to Dict(String, String)
  let filters_dict =
    generic_dictionary.to_string_dict(
      slo.typed_instatiation_of_query_templatized_variables,
    )

  use resolve_sli <- result.try(resolve_sli(filters_dict, sli_type))

  Ok(resolved_slo.Slo(
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
) -> Result(resolved_sli.Sli, String) {
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

  // Resolve the CQL query by substituting words with resolved query values
  use resolved_query <- result.try(resolve_cql_query(
    sli_type.query_template_type.query,
    resolved_queries,
  ))

  Ok(resolved_sli.Sli(
    query_template_type: sli_type.query_template_type,
    metric_attributes: resolved_queries,
    resolved_query: resolved_query,
  ))
}

fn resolve_cql_query(
  query: parser.ExpContainer,
  resolved_queries: dict.Dict(String, String),
) -> Result(parser.ExpContainer, String) {
  case query {
    parser.ExpContainer(exp) -> {
      use resolved_exp <- result.try(resolve_exp(exp, resolved_queries))
      Ok(parser.ExpContainer(resolved_exp))
    }
  }
}

fn resolve_exp(
  exp: parser.Exp,
  resolved_queries: dict.Dict(String, String),
) -> Result(parser.Exp, String) {
  case exp {
    parser.OperatorExpr(left, right, op) -> {
      use resolved_left <- result.try(resolve_exp(left, resolved_queries))
      use resolved_right <- result.try(resolve_exp(right, resolved_queries))
      Ok(parser.OperatorExpr(resolved_left, resolved_right, op))
    }
    parser.Primary(primary) -> {
      use resolved_primary <- result.try(resolve_primary(primary, resolved_queries))
      Ok(parser.Primary(resolved_primary))
    }
  }
}

fn resolve_primary(
  primary: parser.Primary,
  resolved_queries: dict.Dict(String, String),
) -> Result(parser.Primary, String) {
  case primary {
    parser.PrimaryWord(word) -> {
      case word {
        parser.Word(word_value) -> {
          case dict.get(resolved_queries, word_value) {
            Ok(resolved_value) -> {
              // Parse the resolved value as a new expression
              case parser.parse_expr(resolved_value) {
                Ok(parsed_exp) -> {
                  case parsed_exp {
                    parser.ExpContainer(exp) -> Ok(parser.PrimaryExp(exp))
                  }
                }
                Error(_) -> {
                  // If parsing fails, treat as a literal word
                  Ok(parser.PrimaryWord(parser.Word(resolved_value)))
                }
              }
            }
            Error(_) -> {
              // Word not found in resolved queries, keep as is
              Ok(parser.PrimaryWord(word))
            }
          }
        }
      }
    }
    parser.PrimaryExp(exp) -> {
      use resolved_exp <- result.try(resolve_exp(exp, resolved_queries))
      Ok(parser.PrimaryExp(resolved_exp))
    }
  }
}
