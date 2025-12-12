/// Datadog Query Template Resolver
///
/// This module defines template types for replacing placeholders in Datadog metric queries.
///
/// Two template formats are supported:
///
/// 1. Simple raw value substitution: `$$INPUT_NAME$$`
///    - Just substitutes the raw value with no formatting
///    - Example: `time_slice(query < $$threshold$$ per 10s)` with threshold=2500000
///      becomes `time_slice(query < 2500000 per 10s)`
///
/// 2. Datadog filter format: `$$INPUT_NAME->DATADOG_ATTR:TEMPLATE_TYPE$$`
///    - INPUT_NAME: The name of the input attribute from the expectation (provides the value)
///    - DATADOG_ATTR: The Datadog tag/attribute name to use in the query
///    - TEMPLATE_TYPE: How the value should be formatted in the query (optional, defaults to tag format)
///    - Example: `$$environment->env$$` with environment="production"
///      becomes `env:production`
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
import caffeine_lang/common/errors
import caffeine_lang/common/helpers.{type ValueTuple}
import gleam/dynamic/decode
import gleam/list
import gleam/option
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
  /// Raw type for simple value substitution without any formatting.
  /// Used when template is just `$$name$$` without `->`.
  /// - String -> just the value itself
  /// - List -> comma-separated values
  Raw

  /// Default type that auto-detects based on value:
  /// - String -> `attr:value` (wildcards in value are preserved)
  /// - List -> `attr IN (value1, value2, ...)`
  Default

  /// Negated filter (auto-detects based on value):
  /// - String -> `!attr:value` (wildcards in value are preserved)
  /// - List -> `attr NOT IN (value1, value2, ...)`
  Not
}

/// High-level parsing and resolution of a templatized query string.
pub fn parse_and_resolve_query_template(
  query: String,
  value_tuples: List(ValueTuple),
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

/// Parses a template variable string. Supports two formats:
///
/// 1. Simple raw value: "INPUT_NAME" (no ->)
///    - Returns Raw type for direct value substitution
///    - Example: "threshold" -> TemplateVariable("threshold", "", Raw)
///
/// 2. Datadog format: "INPUT_NAME->DATADOG_ATTR:TEMPLATE_TYPE"
///    - Returns Default or Not type for Datadog filter formatting
///    - Example: "environment->env" -> TemplateVariable("environment", "env", Default)
///    - Example: "environment->env:not" -> TemplateVariable("environment", "env", Not)
@internal
pub fn parse_template_variable(
  variable: String,
) -> Result(TemplateVariable, errors.SemanticError) {
  case string.split_once(variable, "->") {
    // No "->" means simple raw value substitution
    Error(_) -> {
      let trimmed = string.trim(variable)
      case trimmed {
        "" ->
          Error(errors.TemplateParseError(
            "Empty template variable name: " <> variable,
          ))
        _ ->
          Ok(TemplateVariable(
            input_name: trimmed,
            datadog_attr: "",
            template_type: Raw,
          ))
      }
    }
    // Has "->" means Datadog format
    Ok(#(input_name, rest)) -> {
      let trimmed_input = string.trim(input_name)

      case trimmed_input, rest {
        "", _ ->
          Error(errors.TemplateParseError(
            "Empty input name in template: " <> variable,
          ))
        _, "" ->
          Error(errors.TemplateParseError(
            "Empty label name in template: " <> variable,
          ))
        _, _ -> parse_datadog_template_variable(trimmed_input, rest)
      }
    }
  }
}

/// Helper to parse Datadog format template variables (with ->)
fn parse_datadog_template_variable(
  input_name: String,
  rest: String,
) -> Result(TemplateVariable, errors.SemanticError) {
  case string.split_once(rest, ":") {
    // No colon means default template type
    Error(_) ->
      Ok(TemplateVariable(
        input_name: string.trim(rest),
        datadog_attr: input_name,
        template_type: Default,
      ))
    Ok(#(datadog_attr, type_string)) -> {
      case parse_template_type(string.trim(type_string)) {
        Error(e) -> Error(e)
        Ok(template_type) ->
          Ok(TemplateVariable(
            input_name: string.trim(datadog_attr),
            datadog_attr: input_name,
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
@internal
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
@internal
pub fn resolve_template(
  template: TemplateVariable,
  value_tuple: ValueTuple,
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
    helpers.Optional(helpers.Dict(_, _)) ->
      Error(errors.TemplateResolutionError(
        "Unsupported templatized variable type: "
        <> helpers.accepted_type_to_string(value_tuple.typ)
        <> ". Dict support is pending, open an issue if this is a desired use case.",
      ))
    helpers.Optional(inner_type) -> {
      // For Optional types, try to decode the inner value
      // If None, return empty string (template gets removed from query)
      let inner_decoder = case inner_type {
        helpers.List(list_inner) ->
          decode.optional(helpers.decode_list_values_to_strings(list_inner))
          |> decode.map(fn(maybe_vals) {
            case maybe_vals {
              option.Some(vals) -> option.Some(resolve_list_value(template, vals))
              option.None -> option.None
            }
          })
        _ ->
          decode.optional(helpers.decode_value_to_string(inner_type))
          |> decode.map(fn(maybe_val) {
            case maybe_val {
              option.Some(val) -> option.Some(resolve_string_value(template, val))
              option.None -> option.None
            }
          })
      }
      let assert Ok(maybe_result) = decode.run(value_tuple.value, inner_decoder)
      case maybe_result {
        option.Some(resolved) -> Ok(resolved)
        option.None -> Ok("")
      }
    }
    helpers.Defaulted(helpers.Dict(_, _), _) ->
      Error(errors.TemplateResolutionError(
        "Unsupported templatized variable type: "
        <> helpers.accepted_type_to_string(value_tuple.typ)
        <> ". Dict support is pending, open an issue if this is a desired use case.",
      ))
    helpers.Defaulted(inner_type, default_val) -> {
      // For Defaulted types, try to decode the inner value
      // If None, use the default value instead of empty string
      let inner_decoder = case inner_type {
        helpers.List(list_inner) ->
          decode.optional(helpers.decode_list_values_to_strings(list_inner))
          |> decode.map(fn(maybe_vals) {
            case maybe_vals {
              option.Some(vals) -> option.Some(resolve_list_value(template, vals))
              option.None -> option.None
            }
          })
        _ ->
          decode.optional(helpers.decode_value_to_string(inner_type))
          |> decode.map(fn(maybe_val) {
            case maybe_val {
              option.Some(val) -> option.Some(resolve_string_value(template, val))
              option.None -> option.None
            }
          })
      }
      let assert Ok(maybe_result) = decode.run(value_tuple.value, inner_decoder)
      case maybe_result {
        option.Some(resolved) -> Ok(resolved)
        // Use default value instead of empty string
        option.None -> Ok(resolve_string_value(template, default_val))
      }
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
@internal
pub fn resolve_string_value(template: TemplateVariable, value: String) -> String {
  let attr = template.datadog_attr
  case template.template_type {
    Raw -> value
    Default -> attr <> ":" <> value
    Not -> "!" <> attr <> ":" <> value
  }
}

/// Formats a list of string values according to the template variable.
/// ASSUMPTION: we already checked the value type is correct and the label matches
///             the Datadog template name. Thus instead of passing in a ValueTuple
///             we can just pass in the raw list value of strings.
@internal
pub fn resolve_list_value(
  template: TemplateVariable,
  values: List(String),
) -> String {
  let attr = template.datadog_attr
  case template.template_type {
    Raw -> values |> string.join(", ")
    Default -> attr <> " IN (" <> values |> string.join(", ") <> ")"
    Not -> attr <> " NOT IN (" <> values |> string.join(", ") <> ")"
  }
}
