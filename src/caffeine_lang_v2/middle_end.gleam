import caffeine_lang_v2/common/helpers.{type AcceptedTypes}
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

pub type SemanticError {
  QueryResolutionError(msg: String)
}

pub type ResolveError {
  ParseError(msg: String)
  ResolveError(msg: String)
  MissingQueryKey(key: String)
}

/// Format a resolve error as a string
pub fn format_resolve_error(error: ResolveError) -> String {
  case error {
    ParseError(msg) -> "CQL parse error: " <> msg
    ResolveError(msg) -> "CQL resolve error: " <> msg
    MissingQueryKey(key) -> "Missing query key: " <> key
  }
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
    |> result_map_error(fn(e) { ParseError(e) }),
  )

  // Resolve to a primitive (currently only GoodOverTotal supported)
  use primitive <- result_try(
    cql_resolver.resolve_primitives(exp_container)
    |> result_map_error(fn(e) { ResolveError(e) }),
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

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
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

  // Resolve CQL expression
  use #(numerator_query, denominator_query) <- result_try(
    resolve_queries(value, queries)
    |> result_map_error(fn(e) { QueryResolutionError(format_resolve_error(e)) }),
  )

  // Build new values with resolved queries, removing value and queries
  let new_values =
    ir.values
    |> list.filter(fn(vt) { vt.label != "value" && vt.label != "queries" })
    |> list.append([
      ValueTuple(
        label: "numerator_query",
        typ: helpers.String,
        value: dynamic.string(numerator_query),
      ),
      ValueTuple(
        label: "denominator_query",
        typ: helpers.String,
        value: dynamic.string(denominator_query),
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
