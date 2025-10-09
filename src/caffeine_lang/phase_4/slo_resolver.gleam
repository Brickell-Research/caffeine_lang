import caffeine_lang/cql/parser
import caffeine_lang/types/ast/organization
import caffeine_lang/types/ast/sli_type
import caffeine_lang/types/ast/slo
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import caffeine_lang/types/resolved/resolved_sli
import caffeine_lang/types/resolved/resolved_slo
import gleam/dict
import gleam/int
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
          Ok(value) -> {
            let processed_value = process_filter_value(value, sli_type, name)
            string.replace(acc, "$$" <> name <> "$$", processed_value)
          }
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
    name: sli_type.name,
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
      use resolved_primary <- result.try(resolve_primary(
        primary,
        resolved_queries,
      ))
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

fn process_filter_value(
  value: String,
  sli_type: sli_type.SliType,
  filter_name: String,
) -> String {
  // Check if this filter is defined as a List type
  case find_filter_type(sli_type, filter_name) {
    Ok(accepted_types.List(inner_type)) -> {
      case inner_type {
        accepted_types.String -> {
          case parse_list_value(value, inner_parse_string) {
            Ok(parsed_list) -> convert_list_to_or_expression(parsed_list)
            Error(_) -> value
          }
        }
        accepted_types.Integer -> {
          case parse_list_value(value, inner_parse_int) {
            Ok(parsed_list) ->
              convert_list_to_or_expression(list.map(parsed_list, int.to_string))
            Error(_) -> value
          }
        }
        _ -> value
      }
    }
    _ -> value
  }
}

pub fn convert_list_to_or_expression(items: List(String)) -> String {
  case items {
    [] -> ""
    [single] -> single
    multiple -> "(" <> string.join(multiple, ",") <> ")"
  }
}

pub fn parse_list_value(
  value: String,
  inner_parse: fn(String) -> Result(a, String),
) -> Result(List(a), String) {
  let splitted = string.split(value, "]")
  let splitted = string.split(string.join(splitted, ""), "[")

  let result =
    string.join(splitted, "")
    |> string.split(",")
    |> list.map(inner_parse)
    |> result.all

  result
}

pub fn inner_parse_string(value: String) -> Result(String, String) {
  let splitted = string.split(value, "\"")
  let result =
    string.join(splitted, "")
    |> string.trim

  Ok(result)
}

pub fn inner_parse_int(value: String) -> Result(Int, String) {
  case int.parse(string.trim(value)) {
    Ok(int_value) -> Ok(int_value)
    Error(_) -> Error("Invalid integer value: " <> value)
  }
}

fn find_filter_type(
  sli_type: sli_type.SliType,
  filter_name: String,
) -> Result(accepted_types.AcceptedTypes, String) {
  sli_type.specification_of_query_templatized_variables
  |> list.find(fn(basic_type) { basic_type.attribute_name == filter_name })
  |> result.map(fn(basic_type) { basic_type.attribute_type })
  |> result.replace_error("Filter type not found")
}
