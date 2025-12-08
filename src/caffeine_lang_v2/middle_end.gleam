import caffeine_lang_v2/common/errors.{
  type ResolveError, type SemanticError, type TemplateError, CqlParseError,
  CqlResolveError, InvalidVariableFormat, MissingAttribute, MissingQueryKey,
  QueryResolutionError, UnterminatedVariable, format_resolve_error,
  format_template_error,
}
import caffeine_lang_v2/common/helpers.{type AcceptedTypes, result_try}
import caffeine_query_language/generator as cql_generator
import caffeine_query_language/parser as cql_parser
import caffeine_query_language/resolver as cql_resolver
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/string

pub type ValueTuple {
  ValueTuple(label: String, typ: AcceptedTypes, value: Dynamic)
}

pub type IntermediateRepresentation {
  IntermediateRepresentation(
    expectation_name: String,
    artifact_ref: String,
    values: List(ValueTuple),
  )
}

/// Resolve CQL expression and substitute query values
/// Returns (numerator_query, denominator_query) tuple
pub fn resolve_queries(
  value: String,
  queries: Dict(String, String),
) -> Result(#(String, String), ResolveError) {
  // Parse the CQL expression
  use exp_container <- result_try(
    cql_parser.parse_expr(value)
    |> result_map_error(fn(e) { CqlParseError(e) }),
  )

  // Resolve to a primitive (currently only GoodOverTotal supported)
  use primitive <- result_try(
    cql_resolver.resolve_primitives(exp_container)
    |> result_map_error(fn(e) { CqlResolveError(e) }),
  )

  // Extract query strings based on the primitive structure
  case primitive {
    cql_resolver.GoodOverTotal(numerator_exp, denominator_exp) -> {
      use numerator_query <- result_try(substitute_exp(numerator_exp, queries))
      use denominator_query <- result_try(substitute_exp(
        denominator_exp,
        queries,
      ))
      Ok(#(numerator_query, denominator_query))
    }
  }
}

/// Substitute variable names in a CQL expression with actual query strings
fn substitute_exp(
  exp: cql_parser.Exp,
  queries: Dict(String, String),
) -> Result(String, ResolveError) {
  case exp {
    cql_parser.Primary(cql_parser.PrimaryWord(cql_parser.Word(key))) -> {
      dict.get(queries, key)
      |> result_map_error(fn(_) { MissingQueryKey(key) })
    }
    cql_parser.Primary(cql_parser.PrimaryExp(inner_exp)) -> {
      use inner <- result_try(substitute_exp(inner_exp, queries))
      Ok("(" <> inner <> ")")
    }
    cql_parser.OperatorExpr(left, right, op) -> {
      use left_str <- result_try(substitute_exp(left, queries))
      use right_str <- result_try(substitute_exp(right, queries))
      let op_str = cql_generator.operator_to_datadog_query(op)
      Ok(left_str <> " " <> op_str <> " " <> right_str)
    }
  }
}

fn result_map_error(
  result: Result(a, e1),
  mapper: fn(e1) -> e2,
) -> Result(a, e2) {
  case result {
    Ok(value) -> Ok(value)
    Error(err) -> Error(mapper(err))
  }
}

/// Execute semantic analysis on a list of IRs
/// This transforms the IR by resolving vendor-specific queries
pub fn execute(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), SemanticError) {
  irs |> list.try_map(execute_one)
}

fn execute_one(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, SemanticError) {
  case ir.artifact_ref, get_vendor(ir) |> normalize_vendor {
    "SLO", Ok("datadog") -> resolve_slo_datadog(ir)
    _, _ -> Ok(ir)
  }
}

fn normalize_vendor(vendor_result: Result(String, Nil)) -> Result(String, Nil) {
  case vendor_result {
    Ok(v) -> Ok(string.lowercase(v))
    Error(e) -> Error(e)
  }
}

fn get_vendor(ir: IntermediateRepresentation) -> Result(String, Nil) {
  ir.values
  |> list.find(fn(vt) { vt.label == "vendor" })
  |> result_map_error(fn(_) { Nil })
  |> result_try(fn(vt) {
    decode.run(vt.value, decode.string)
    |> result_map_error(fn(_) { Nil })
  })
}

fn resolve_slo_datadog(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, SemanticError) {
  // Extract value and queries from IR values
  use value <- result_try(
    get_string_from_values(ir.values, "value")
    |> result_map_error(fn(_) {
      QueryResolutionError("Missing 'value' field for SLO")
    }),
  )
  use queries <- result_try(
    get_string_dict_from_values(ir.values, "queries")
    |> result_map_error(fn(_) {
      QueryResolutionError("Missing 'queries' field for SLO")
    }),
  )

  // Build attributes from all string values in the IR for template replacement
  let attributes = extract_string_attributes(ir.values)

  // Resolve CQL expression
  use #(numerator_query, denominator_query) <- result_try(
    resolve_queries(value, queries)
    |> result_map_error(fn(e) { QueryResolutionError(format_resolve_error(e)) }),
  )

  // Apply template replacement to both queries
  use numerator_query_resolved <- result_try(
    replace_template_variables(numerator_query, attributes)
    |> result_map_error(fn(e) {
      QueryResolutionError(format_template_error(e))
    }),
  )
  use denominator_query_resolved <- result_try(
    replace_template_variables(denominator_query, attributes)
    |> result_map_error(fn(e) {
      QueryResolutionError(format_template_error(e))
    }),
  )

  // Build new values with resolved queries, removing value and queries
  let new_values =
    ir.values
    |> list.filter(fn(vt) { vt.label != "value" && vt.label != "queries" })
    |> list.append([
      ValueTuple(
        label: "numerator_query",
        typ: helpers.String,
        value: dynamic.string(numerator_query_resolved),
      ),
      ValueTuple(
        label: "denominator_query",
        typ: helpers.String,
        value: dynamic.string(denominator_query_resolved),
      ),
    ])

  Ok(IntermediateRepresentation(..ir, values: new_values))
}

fn get_string_from_values(
  values: List(ValueTuple),
  key: String,
) -> Result(String, Nil) {
  values
  |> list.find(fn(vt) { vt.label == key })
  |> result_try(fn(vt) {
    decode.run(vt.value, decode.string)
    |> result_map_error(fn(_) { Nil })
  })
}

fn get_string_dict_from_values(
  values: List(ValueTuple),
  key: String,
) -> Result(Dict(String, String), Nil) {
  values
  |> list.find(fn(vt) { vt.label == key })
  |> result_try(fn(vt) {
    decode.run(vt.value, decode.dict(decode.string, decode.string))
    |> result_map_error(fn(_) { Nil })
  })
}

/// Extract all string-typed values from a list of ValueTuples as a dict
/// This is used to build the attributes dict for template replacement
fn extract_string_attributes(values: List(ValueTuple)) -> Dict(String, String) {
  values
  |> list.filter_map(fn(vt) {
    case decode.run(vt.value, decode.string) {
      Ok(str_value) -> Ok(#(vt.label, str_value))
      Error(_) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Parse a template variable in the format "ATTRIBUTE_NAME->TEMPLATE_NAME"
/// Returns the attribute name and template name as a tuple
pub fn parse_template_variable(
  variable: String,
) -> Result(#(String, String), TemplateError) {
  case string.split_once(variable, "->") {
    Ok(#(attribute, template)) -> {
      case attribute, template {
        "", _ -> Error(InvalidVariableFormat(variable))
        _, "" -> Error(InvalidVariableFormat(variable))
        _, _ -> Ok(#(attribute, template))
      }
    }
    Error(_) -> Error(InvalidVariableFormat(variable))
  }
}

/// Extract all template variables from a templatized string
/// Variables are in the format $$ATTRIBUTE_NAME->TEMPLATE_NAME$$
/// Returns a list of variable strings (without the $$ delimiters)
pub fn extract_template_variables_from_string(
  templatized_string: String,
) -> Result(List(String), TemplateError) {
  extract_variables_recursive(templatized_string, [])
}

fn extract_variables_recursive(
  remaining: String,
  acc: List(String),
) -> Result(List(String), TemplateError) {
  case string.split_once(remaining, "$$") {
    Error(_) -> Ok(list.reverse(acc))
    Ok(#(_before, after_open)) -> {
      case string.split_once(after_open, "$$") {
        Error(_) -> Error(UnterminatedVariable(after_open))
        Ok(#(variable, after_close)) -> {
          // Validate the variable format
          use _ <- result_try(
            parse_template_variable(variable)
            |> result_map_error(fn(e) { e }),
          )
          extract_variables_recursive(after_close, [variable, ..acc])
        }
      }
    }
  }
}

/// Replace template variables in a string with values from a dictionary
/// The dictionary is keyed by attribute name
pub fn replace_template_variables(
  templatized_string: String,
  replacements: Dict(String, String),
) -> Result(String, TemplateError) {
  replace_variables_recursive(templatized_string, replacements, "")
}

fn replace_variables_recursive(
  remaining: String,
  replacements: Dict(String, String),
  acc: String,
) -> Result(String, TemplateError) {
  case string.split_once(remaining, "$$") {
    Error(_) -> Ok(acc <> remaining)
    Ok(#(before, after_open)) -> {
      case string.split_once(after_open, "$$") {
        Error(_) -> Error(UnterminatedVariable(after_open))
        Ok(#(variable, after_close)) -> {
          // Parse the variable to get attribute name
          use #(attribute, _template) <- result_try(
            parse_template_variable(variable),
          )
          // Look up the replacement value
          use value <- result_try(
            dict.get(replacements, attribute)
            |> result_map_error(fn(_) { MissingAttribute(attribute) }),
          )
          replace_variables_recursive(
            after_close,
            replacements,
            acc <> before <> value,
          )
        }
      }
    }
  }
}
