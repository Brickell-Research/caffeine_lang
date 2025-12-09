import caffeine_lang_v2/common/errors
import caffeine_lang_v2/common/helpers.{type ValueTuple}
import caffeine_lang_v2/middle_end/templatizer
import caffeine_lang_v2/middle_end/vendor.{type Vendor}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/result

pub type IntermediateRepresentation {
  IntermediateRepresentation(
    expectation_name: String,
    artifact_ref: String,
    values: List(ValueTuple),
    // TODO: make this cleaner. An option is weird.
    vendor: Option(Vendor),
  )
}

pub fn resolve_intermediate_representations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), errors.SemanticError) {
  irs
  |> list.try_map(fn(ir) {
    use ir_with_vendor <- result.try(resolve_vendor(ir))
    resolve_queries(ir_with_vendor)
  })
}

pub fn resolve_vendor(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, errors.SemanticError) {
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
      use vendor_value <- result.try(vendor.resolve_vendor(vendor_string))

      Ok(IntermediateRepresentation(..ir, vendor: option.Some(vendor_value)))
    }
  }
}

pub fn resolve_queries(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, errors.SemanticError) {
  case ir.vendor {
    option.Some(vendor.Datadog) -> {
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
    _ ->
      Error(errors.TemplateResolutionError(
        "No vendor for expectation: " <> ir.expectation_name,
      ))
  }
}
