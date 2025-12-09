import caffeine_lang_v2/common/errors
import caffeine_lang_v2/common/helpers.{type ValueTuple}
import caffeine_lang_v2/middle_end/templatizer
import caffeine_lang_v2/middle_end/vendor.{type Vendor}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/result

pub type IntermediateRepresentation {
  IntermediateRepresentation(
    expectation_name: String,
    artifact_ref: String,
    values: List(ValueTuple),
  )
}

pub fn resolve_vendor(
  ir: IntermediateRepresentation,
) -> Result(Vendor, errors.SemanticError) {
  case
    ir.values
    |> list.filter(fn(value) { value.label == "vendor" })
    |> list.first
  {
    Error(_) ->
      Error(errors.VendorResolutionError(
        "No vendor input for: " <> ir.expectation_name,
      ))
    Ok(vendor_value_tuple) -> {
      // ok to assert since already type checked in parser phase
      let assert Ok(vendor_string) =
        decode.run(vendor_value_tuple.value, decode.string)
      vendor.resolve_vendor(vendor_string)
    }
  }
}

pub fn resolve_queries(
  ir: IntermediateRepresentation,
  vendor: Vendor,
) -> Result(IntermediateRepresentation, errors.SemanticError) {
  case vendor {
    vendor.Datadog -> {
      let assert Ok(queries_value_tuple) =
        ir.values
        |> list.filter(fn(vt) { vt.label == "queries" })
        |> list.first

      let assert Ok(queries_dict) =
        decode.run(
          queries_value_tuple.value,
          decode.dict(decode.string, decode.string),
        )

      // Resolve all queries and collect results
      use resolved_queries <- result.try(
        queries_dict
        |> dict.to_list
        |> list.try_map(fn(pair) {
          let #(key, query) = pair
          use resolved <- result.map(
            templatizer.parse_and_resolve_query_template(query, ir.values),
          )
          #(key, resolved)
        }),
      )

      // Build the new queries dict as a dynamic value
      let resolved_queries_dynamic =
        resolved_queries
        |> list.map(fn(pair) {
          let #(key, value) = pair
          #(dynamic.string(key), dynamic.string(value))
        })
        |> dynamic.properties

      // Create the new queries ValueTuple
      let new_queries_value_tuple =
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          resolved_queries_dynamic,
        )

      // Update the IR with the resolved queries
      let new_values =
        ir.values
        |> list.map(fn(vt) {
          case vt.label == "queries" {
            True -> new_queries_value_tuple
            False -> vt
          }
        })

      Ok(IntermediateRepresentation(..ir, values: new_values))
    }
  }
}
