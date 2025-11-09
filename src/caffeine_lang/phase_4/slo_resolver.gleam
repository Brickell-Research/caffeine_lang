import caffeine_lang/phase_2/linker/organization
import caffeine_lang/phase_2/linker/sli_type
import caffeine_lang/phase_2/linker/slo
import caffeine_lang/phase_4/resolved_sli
import caffeine_lang/phase_4/resolved_slo
import caffeine_lang/types/common/accepted_types
import caffeine_lang/types/common/generic_dictionary
import caffeine_query_language/parser
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

  use resolve_sli <- result.try(resolve_sli(filters_dict, sli_type, slo.name))

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
  slo_name: String,
) -> Result(resolved_sli.Sli, String) {
  use resolved_queries <- result.try(
    sli_type.typed_instatiation_of_query_templates
    |> generic_dictionary.to_string_dict
    |> dict.to_list
    |> list.try_map(fn(pair) {
      let #(metric_attribute, template) = pair

      // Process all template variables in the template string
      use processed <- result.try(process_template_string(
        template,
        filters,
        sli_type,
      ))
      Ok(#(metric_attribute, processed))
    })
    |> result.map(dict.from_list),
  )

  // Resolve the CQL query by substituting words with resolved query values
  use resolved_query <- result.try(resolve_cql_query(
    sli_type.query_template_type.query,
    resolved_queries,
  ))

  Ok(resolved_sli.Sli(
    name: slo_name,
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

// Process a complete template string, finding and replacing all template variables
fn process_template_string(
  template: String,
  filters: dict.Dict(String, String),
  sli_type: sli_type.SliType,
) -> Result(String, String) {
  // Find all template variables by splitting on $$
  let parts = string.split(template, "$$")

  // Process parts: odd indices are template variables, even indices are literal text
  use result <- result.try(process_template_parts(
    parts,
    [],
    filters,
    sli_type,
    False,
  ))

  // Clean up any remaining comma issues and convert to AND syntax
  let cleaned = cleanup_empty_optionals(result)
  Ok(convert_commas_to_and(cleaned))
}

// Helper to process template parts alternating between literal text and variables
fn process_template_parts(
  parts: List(String),
  acc: List(String),
  filters: dict.Dict(String, String),
  sli_type: sli_type.SliType,
  is_variable: Bool,
) -> Result(String, String) {
  case parts {
    [] -> Ok(string.join(list.reverse(acc), ""))
    [part, ..rest] -> {
      case is_variable {
        False -> {
          // This is literal text, keep as is
          process_template_parts(rest, [part, ..acc], filters, sli_type, True)
        }
        True -> {
          // This is a template variable, process it
          use replacement <- result.try(process_template_variable(
            part,
            filters,
            sli_type,
          ))
          process_template_parts(
            rest,
            [replacement, ..acc],
            filters,
            sli_type,
            False,
          )
        }
      }
    }
  }
}

// Clean up hanging commas and spaces from empty optional fields
// This handles edge cases where multiple consecutive optional fields are missing
fn cleanup_empty_optionals(query: String) -> String {
  query
  // Remove multiple consecutive ", , " patterns (handles 2+ missing optionals)
  |> string.replace(", , , ", ", ")
  |> string.replace(", , ", ", ")
  // Remove leading comma after opening brace (all initial optionals missing)
  |> string.replace("{, ", "{")
  // Remove trailing comma before closing brace (all trailing optionals missing)
  |> string.replace(", }", "}")
  // Remove trailing comma before closing paren
  |> string.replace(", )", ")")
  // Handle case where only commas remain in braces
  |> string.replace("{,}", "{}")
}

// Convert comma-separated tags to AND-separated tags for Datadog queries
// Datadog requires AND operators when there are OR expressions in the query
fn convert_commas_to_and(query: String) -> String {
  // Only convert if the query contains OR expressions (parentheses with OR)
  // Otherwise, Datadog accepts comma-separated tags
  case string.contains(query, " OR ") {
    True -> convert_commas_in_braces(query, "", False)
    False -> query
  }
}

// Helper function to replace commas with AND only inside curly braces
fn convert_commas_in_braces(
  remaining: String,
  acc: String,
  inside_braces: Bool,
) -> String {
  case string.pop_grapheme(remaining) {
    Ok(#("{", rest)) -> {
      // Entering braces
      convert_commas_in_braces(rest, acc <> "{", True)
    }
    Ok(#("}", rest)) -> {
      // Exiting braces
      convert_commas_in_braces(rest, acc <> "}", False)
    }
    Ok(#(",", rest)) -> {
      case inside_braces {
        True -> {
          // Inside braces, replace comma with " AND "
          // Check if followed by space to avoid double spaces
          case string.pop_grapheme(rest) {
            Ok(#(" ", rest2)) -> {
              // Replace ", " with " AND "
              convert_commas_in_braces(rest2, acc <> " AND ", True)
            }
            _ -> {
              // Replace "," with " AND " (no space after comma)
              convert_commas_in_braces(rest, acc <> " AND ", True)
            }
          }
        }
        False -> {
          // Outside braces, keep comma as is
          convert_commas_in_braces(rest, acc <> ",", False)
        }
      }
    }
    Ok(#(char, rest)) -> {
      // Any other character, keep it
      convert_commas_in_braces(rest, acc <> char, inside_braces)
    }
    Error(_) -> {
      // End of string
      acc
    }
  }
}

// Parse and process a single template variable
fn process_template_variable(
  template_var: String,
  filters: dict.Dict(String, String),
  sli_type: sli_type.SliType,
) -> Result(String, String) {
  // Parse the template variable to extract components
  use #(field_name, var_name, is_negated) <- result.try(parse_template_variable(
    template_var,
  ))

  // Check if this is an optional type
  case find_filter_type(sli_type, var_name) {
    Ok(accepted_types.Optional(_)) -> {
      // For optional types, if not provided, return empty string
      case dict.get(filters, var_name) {
        Ok(value) -> {
          use processed_value <- result.try(process_filter_value(
            value,
            sli_type,
            var_name,
            field_name,
          ))

          // Apply negation if needed
          case is_negated {
            True -> Ok("NOT (" <> processed_value <> ")")
            False -> Ok(processed_value)
          }
        }
        Error(_) -> Ok("")
      }
    }
    _ -> {
      // For non-optional types, require the value
      case dict.get(filters, var_name) {
        Ok(value) -> {
          // Process the value based on its type
          use processed_value <- result.try(process_filter_value(
            value,
            sli_type,
            var_name,
            field_name,
          ))

          // Apply negation if needed
          case is_negated {
            True -> Ok("NOT (" <> processed_value <> ")")
            False -> Ok(processed_value)
          }
        }
        Error(_) ->
          Error("Template variable '" <> var_name <> "' not found in filters")
      }
    }
  }
}

// Parse template variable string to extract field name, variable name, and negation flag
// Input: "$$field->var$$" or "$$NOT[field->var]$$"
// Output: #(field_name, var_name, is_negated)
fn parse_template_variable(
  template_var: String,
) -> Result(#(String, String, Bool), String) {
  // Remove $$ markers
  let content =
    template_var
    |> string.replace("$$", "")

  // Check for NOT prefix
  let #(content, is_negated) = case string.starts_with(content, "NOT[") {
    True -> {
      let inner =
        content
        |> string.replace("NOT[", "")
        |> string.replace("]", "")
      #(inner, True)
    }
    False -> #(content, False)
  }

  // Split by -> to get field and variable name
  case string.split(content, "->") {
    [field_name, var_name] -> Ok(#(field_name, var_name, is_negated))
    _ ->
      Error(
        "Invalid template variable format: "
        <> template_var
        <> ". Expected $$field->var$$ or $$NOT[field->var]$$",
      )
  }
}

fn process_filter_value(
  value: String,
  sli_type: sli_type.SliType,
  filter_name: String,
  field_name: String,
) -> Result(String, String) {
  // Check the filter type
  case find_filter_type(sli_type, filter_name) {
    Ok(accepted_types.NonEmptyList(inner_type)) -> {
      case inner_type {
        accepted_types.String -> {
          case parse_list_value(value, inner_parse_string) {
            Ok(parsed_list) -> {
              case parsed_list {
                [] ->
                  Error(
                    "Empty list not allowed for NonEmptyList field '"
                    <> filter_name
                    <> "': must contain at least one value",
                  )
                _ -> Ok(convert_list_to_or_expression(parsed_list, field_name))
              }
            }
            Error(err) ->
              Error(
                "Error parsing NonEmptyList field '"
                <> filter_name
                <> "': "
                <> err,
              )
          }
        }
        accepted_types.Integer -> {
          case parse_list_value(value, inner_parse_int) {
            Ok(parsed_list) -> {
              case parsed_list {
                [] ->
                  Error(
                    "Empty list not allowed for NonEmptyList field '"
                    <> filter_name
                    <> "': must contain at least one value",
                  )
                _ ->
                  Ok(convert_list_to_or_expression(
                    list.map(parsed_list, int.to_string),
                    field_name,
                  ))
              }
            }
            Error(err) ->
              Error(
                "Error parsing NonEmptyList field '"
                <> filter_name
                <> "': "
                <> err,
              )
          }
        }
        _ -> Ok(field_name <> ":" <> value)
      }
    }
    Ok(accepted_types.Optional(inner_type)) -> {
      // For optional types, process the inner type
      case inner_type {
        accepted_types.NonEmptyList(list_inner_type) -> {
          // Handle Optional(NonEmptyList(...))
          case list_inner_type {
            accepted_types.String -> {
              case parse_list_value(value, inner_parse_string) {
                Ok(parsed_list) -> {
                  case parsed_list {
                    [] ->
                      Error(
                        "Empty list not allowed for NonEmptyList field '"
                        <> filter_name
                        <> "': must contain at least one value",
                      )
                    _ ->
                      Ok(convert_list_to_or_expression(parsed_list, field_name))
                  }
                }
                Error(err) ->
                  Error(
                    "Error parsing NonEmptyList field '"
                    <> filter_name
                    <> "': "
                    <> err,
                  )
              }
            }
            accepted_types.Integer -> {
              case parse_list_value(value, inner_parse_int) {
                Ok(parsed_list) -> {
                  case parsed_list {
                    [] ->
                      Error(
                        "Empty list not allowed for NonEmptyList field '"
                        <> filter_name
                        <> "': must contain at least one value",
                      )
                    _ ->
                      Ok(convert_list_to_or_expression(
                        list.map(parsed_list, int.to_string),
                        field_name,
                      ))
                  }
                }
                Error(err) ->
                  Error(
                    "Error parsing NonEmptyList field '"
                    <> filter_name
                    <> "': "
                    <> err,
                  )
              }
            }
            _ -> Ok(field_name <> ":" <> value)
          }
        }
        accepted_types.String -> Ok(field_name <> ":" <> value)
        accepted_types.Integer -> Ok(field_name <> ":" <> value)
        accepted_types.Boolean -> Ok(field_name <> ":" <> value)
        accepted_types.Decimal -> Ok(field_name <> ":" <> value)
        _ -> Ok(field_name <> ":" <> value)
      }
    }
    _ -> Ok(field_name <> ":" <> value)
  }
}

pub fn convert_list_to_or_expression(
  items: List(String),
  field_name: String,
) -> String {
  case items {
    [] -> "[]"
    [single] -> {
      // Check if the value contains special characters that could be parsed as operators
      // If so, wrap in parentheses to prevent CQL parsing issues
      let value = field_name <> ":" <> single
      case
        string.contains(single, "*")
        || string.contains(single, "+")
        || string.contains(single, "-")
        || string.contains(single, "/")
      {
        True -> "(" <> value <> ")"
        False -> value
      }
    }
    _multiple -> {
      let or_parts = list.map(items, fn(item) { field_name <> ":" <> item })
      "(" <> string.join(or_parts, " OR ") <> ")"
    }
  }
}

pub fn parse_list_value(
  value: String,
  inner_parse: fn(String) -> Result(a, String),
) -> Result(List(a), String) {
  let splitted = string.split(value, "]")
  let splitted = string.split(string.join(splitted, ""), "[")

  let content = string.join(splitted, "") |> string.trim

  // Handle empty list case
  case content {
    "" -> Error("Empty list not allowed: list must contain at least one value")
    _ -> {
      let parse_result =
        content
        |> string.split(",")
        |> list.map(inner_parse)
        |> result.all

      case parse_result {
        Error(parse_error) ->
          Error("Failed to parse list values: " <> parse_error)
        Ok(parsed_list) -> Ok(parsed_list)
      }
    }
  }
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
