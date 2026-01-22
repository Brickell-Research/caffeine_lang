import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers.{type ValueTuple}
import caffeine_lang/common/primitive_types
import caffeine_lang/middle_end/templatizer
import caffeine_lang/middle_end/vendor.{type Vendor}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// Internal representation of a parsed expectation with metadata and values.
pub type IntermediateRepresentation {
  IntermediateRepresentation(
    metadata: IntermediateRepresentationMetaData,
    unique_identifier: String,
    artifact_refs: List(String),
    values: List(ValueTuple),
    // TODO: make this cleaner. An option is weird.
    vendor: Option(Vendor),
  )
}

/// Metadata associated with an intermediate representation including organization and service identifiers.
pub type IntermediateRepresentationMetaData {
  IntermediateRepresentationMetaData(
    friendly_label: String,
    org_name: String,
    service_name: String,
    blueprint_name: String,
    team_name: String,
    // Metadata specific to any given expectation.
    misc: dict.Dict(String, String),
  )
}

/// Resolves vendor and queries for a list of intermediate representations.
@internal
pub fn resolve_intermediate_representations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  irs
  |> list.try_map(fn(ir) {
    case ir.artifact_refs |> list.contains("SLO") {
      True -> {
        use ir_with_vendor <- result.try(resolve_vendor(ir))
        resolve_queries(ir_with_vendor)
      }
      False -> Ok(ir)
    }
  })
}

/// Resolves the vendor string to a Vendor type for an intermediate representation.
@internal
pub fn resolve_vendor(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, CompilationError) {
  case
    ir.values
    |> list.filter(fn(value) { value.label == "vendor" })
    |> list.first
  {
    Error(_) ->
      Error(errors.SemanticAnalysisVendorResolutionError(
        msg: "No vendor input for: " <> ir.unique_identifier,
      ))
    Ok(vendor_value_tuple) -> {
      // Safe to assert since already type checked in parser phase.
      let assert Ok(vendor_string) =
        decode.run(vendor_value_tuple.value, decode.string)
      let vendor_value = vendor.resolve_vendor(vendor_string)

      Ok(IntermediateRepresentation(..ir, vendor: option.Some(vendor_value)))
    }
  }
}

/// Resolves query templates in an intermediate representation.
@internal
pub fn resolve_queries(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, CompilationError) {
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

      // Resolve all queries and collect results.
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

      // Build the new queries dict as a dynamic value.
      let resolved_queries_dynamic =
        resolved_queries
        |> list.map(fn(pair) {
          let #(key, value) = pair
          #(dynamic.string(key), dynamic.string(value))
        })
        |> dynamic.properties

      // Create the new queries ValueTuple.
      let new_queries_value_tuple =
        helpers.ValueTuple(
          "queries",
          accepted_types.CollectionType(collection_types.Dict(
            accepted_types.PrimitiveType(primitive_types.String),
            accepted_types.PrimitiveType(primitive_types.String),
          )),
          resolved_queries_dynamic,
        )

      // Also resolve templates in the "value" field if present.
      let value_tuple_result =
        ir.values
        |> list.filter(fn(vt) { vt.label == "value" })
        |> list.first

      use resolved_value_tuple <- result.try(case value_tuple_result {
        Error(_) -> Ok(option.None)
        Ok(value_tuple) -> {
          let assert Ok(value_string) =
            decode.run(value_tuple.value, decode.string)
          case
            templatizer.parse_and_resolve_query_template(
              value_string,
              ir.values,
            )
          {
            Ok(resolved_value) ->
              Ok(
                option.Some(helpers.ValueTuple(
                  "value",
                  accepted_types.PrimitiveType(primitive_types.String),
                  dynamic.string(resolved_value),
                )),
              )
            Error(err) -> Error(err)
          }
        }
      })

      // Update the IR with the resolved queries and value.
      let new_values =
        ir.values
        |> list.map(fn(vt) {
          case vt.label {
            "queries" -> new_queries_value_tuple
            "value" ->
              case resolved_value_tuple {
                option.Some(new_value) -> new_value
                option.None -> vt
              }
            _ -> vt
          }
        })

      Ok(IntermediateRepresentation(..ir, values: new_values))
    }
    _ ->
      Error(errors.SemanticAnalysisTemplateResolutionError(
        msg: "No vendor for expectation: " <> ir.unique_identifier,
      ))
  }
}
