/// Datadog Query Template Resolver
///
/// This module defines template types for replacing placeholders in Datadog metric queries.
/// Templates use the format `$$INPUT_NAME->DATADOG_ATTR:TEMPLATE_TYPE$$` where:
/// - INPUT_NAME: The name of the input attribute from the expectation (provides the value)
/// - DATADOG_ATTR: The Datadog tag/attribute name to use in the query
/// - TEMPLATE_TYPE: How the value should be formatted in the query
///
/// Example:
///   Template: `$$environment->env:tag$$`
///   Input: (environment, "production", String)
///   Output: `env:production`
///
/// Datadog Query Syntax Reference:
/// - Tag filters: `{tag:value}` or `{tag:value, tag2:value2}`
/// - Boolean operators: AND, OR, NOT (or symbolic: !)
/// - Wildcards: `tag:prefix*` or `tag:*suffix`
/// - IN operator: `tag IN (value1, value2, value3)`
/// - NOT IN operator: `tag NOT IN (value1, value2)`
///
/// Sources:
/// - https://docs.datadoghq.com/metrics/advanced-filtering/
/// - https://www.datadoghq.com/blog/boolean-filtered-metric-queries/
/// - https://www.datadoghq.com/blog/wildcard-filter-queries/
import caffeine_lang_v2/common/errors
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end/semantic_analyzer
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string

/// A parsed template variable containing all the information needed for substitution.
pub type TemplateVariable {
  TemplateVariable(
    /// The name of the input attribute from the expectation (provides the value)
    input_name: String,
    /// The Datadog tag/attribute name to use in the query
    datadog_attr: String,
    /// How the value should be formatted
    template_type: DatadogTemplateType,
  )
}

/// Template types for Datadog query value replacement.
/// Each type defines how an input value should be formatted in the final query.
///
/// Most formatting is auto-detected from the value:
/// - String -> `attr:value`
/// - List -> `attr IN (value1, value2, ...)`
/// - Value containing `*` -> wildcard preserved as-is
///
/// The only explicit type needed is `Not` for negation.
pub type DatadogTemplateType {
  /// Default type that auto-detects based on value:
  /// - String -> `attr:value` (wildcards in value are preserved)
  /// - List -> `attr IN (value1, value2, ...)`
  Default

  /// Negated filter (auto-detects based on value):
  /// - String -> `!attr:value` (wildcards in value are preserved)
  /// - List -> `attr NOT IN (value1, value2, ...)`
  Not
}

/// The high level full parsing and resolution of a templatized query string.
pub fn parse_and_resolve_query_template(
  query: String,
  value_tuples: List(semantic_analyzer.ValueTuple),
) -> Result(String, errors.SemanticError) {
  case string.split_once(query, "$$") {
    // no more `$$`
    Error(_) -> Ok(query)
    Ok(#(before, rest)) -> {
      case string.split_once(rest, "$$") {
        Error(_) ->
          Error(errors.TemplateParseError(
            "Unexpected incomplete `$$` for substring: " <> query,
          ))
        Ok(#(inside, rest)) -> {
          use rest_of_items <- result.try(parse_and_resolve_query_template(
            rest,
            value_tuples,
          ))

          use template <- result.try(parse_template_variable(inside))
          use value_tuple <- result.try(
            case
              value_tuples
              |> list.filter(fn(vt) { vt.label == template.input_name })
              |> list.first
            {
              Error(_) ->
                Error(errors.TemplateParseError(
                  "Missing input for template: " <> template.input_name,
                ))
              Ok(value_tuple) -> Ok(value_tuple)
            },
          )
          use resolved_template <- result.try(resolve_template(
            template,
            value_tuple,
          ))

          Ok(before <> resolved_template <> rest_of_items)
        }
      }
    }
  }
}

/// Parses a template variable string in the format "INPUT_NAME->DATADOG_ATTR:TEMPLATE_TYPE"
/// or "INPUT_NAME->DATADOG_ATTR" (template type defaults to Default).
///
/// Examples:
/// - "environment->env" -> TemplateVariable("environment", "env", Default)
/// - "environment->env:not" -> TemplateVariable("environment", "env", Not)
/// - "service->service:prefix" -> TemplateVariable("service", "service", PrefixWildcard)
/// - "threshold->:raw" -> TemplateVariable("threshold", "", Raw)
pub fn parse_template_variable(
  variable: String,
) -> Result(TemplateVariable, errors.SemanticError) {
  use #(trimmed_input, rest) <- result.try(
    case string.split_once(variable, "->") {
      Error(_) ->
        Error(errors.TemplateParseError(
          "Invalid template format, missing '->': " <> variable,
        ))
      Ok(#(input_name, rest)) -> {
        let splitted_trimmed = string.trim(input_name)

        case splitted_trimmed, rest {
          "", _ ->
            Error(errors.TemplateParseError(
              "Empty input name in template: " <> variable,
            ))
          _, "" ->
            Error(errors.TemplateParseError(
              "Empty label name in template: " <> variable,
            ))
          _, _ -> Ok(#(splitted_trimmed, rest))
        }
      }
    },
  )
  case string.split_once(rest, ":") {
    // No colon means default template type
    Error(_) ->
      Ok(TemplateVariable(
        input_name: string.trim(rest),
        datadog_attr: trimmed_input,
        template_type: Default,
      ))
    Ok(#(datadog_attr, type_string)) -> {
      case parse_template_type(string.trim(type_string)) {
        Error(e) -> Error(e)
        Ok(template_type) ->
          Ok(TemplateVariable(
            input_name: string.trim(datadog_attr),
            datadog_attr: trimmed_input,
            template_type: template_type,
          ))
      }
    }
  }
}

/// Parses a template type string into a DatadogTemplateType.
///
/// Supported template type strings:
/// - "not" -> Not
pub fn parse_template_type(
  type_string: String,
) -> Result(DatadogTemplateType, errors.SemanticError) {
  case type_string {
    "not" -> Ok(Not)
    _ ->
      Error(errors.TemplateParseError("Unknown template type: " <> type_string))
  }
}

/// Given a parsed template and a parsed value tuple, resolve the templatized string.
/// ASSUMPTION: we already checked the value type is correct in the parser phase.
pub fn resolve_template(
  template: TemplateVariable,
  value_tuple: semantic_analyzer.ValueTuple,
) -> Result(String, errors.SemanticError) {
  use _ <- result.try(case template.input_name == value_tuple.label {
    True -> Ok(True)
    _ ->
      Error(errors.TemplateResolutionError(
        "Mismatch between template input name ("
        <> template.input_name
        <> ") and input value label ("
        <> value_tuple.label
        <> ").",
      ))
  })

  case value_tuple.typ {
    helpers.Dict(_, _) ->
      Error(errors.TemplateResolutionError(
        "Unsupported templatized variable type: "
        <> helpers.accepted_type_to_string(value_tuple.typ)
        <> ". Dict support is pending, open an issue if this is a desired use case.",
      ))
    helpers.List(inner_type) -> {
      let assert Ok(vals) =
        decode.run(
          value_tuple.value,
          helpers.decode_list_values_to_strings(inner_type),
        )
      Ok(resolve_list_value(template, vals))
    }
    _ -> {
      let assert Ok(val) =
        decode.run(
          value_tuple.value,
          helpers.decode_value_to_string(value_tuple.typ),
        )
      Ok(resolve_string_value(template, val))
    }
  }
}

/// Formats a string value according to the template variable.
/// Returns the formatted string ready for insertion into a Datadog query.
/// Wildcards in the value are preserved as-is.
/// ASSUMPTION: we already checked the value type is correct and the label matches
///             the Datadog template name. Thus instead of passing in a ValueTuple
///             we can just pass in the raw string value.
pub fn resolve_string_value(template: TemplateVariable, value: String) -> String {
  let attr = template.datadog_attr
  case template.template_type {
    Default -> attr <> ":" <> value
    Not -> "!" <> attr <> ":" <> value
  }
}

/// Formats a list of string values according to the template variable.
/// ASSUMPTION: we already checked the value type is correct and the label matches
///             the Datadog template name. Thus instead of passing in a ValueTuple
///             we can just pass in the raw list value of strings.
pub fn resolve_list_value(
  template: TemplateVariable,
  values: List(String),
) -> String {
  let attr = template.datadog_attr
  case template.template_type {
    Default -> attr <> " IN (" <> values |> string.join(", ") <> ")"
    Not -> attr <> " NOT IN (" <> values |> string.join(", ") <> ")"
  }
}
