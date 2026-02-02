import caffeine_lang/analysis/templatizer
import caffeine_lang/analysis/vendor.{type Vendor}
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers.{type ValueTuple}
import caffeine_lang/linker/artifacts.{type ArtifactType, SLO}
import caffeine_lang/types.{
  CollectionType, Dict, PrimitiveType, String as StringType,
}
import caffeine_lang/value
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// Internal representation of a parsed expectation with metadata and values.
pub type IntermediateRepresentation {
  IntermediateRepresentation(
    metadata: IntermediateRepresentationMetaData,
    unique_identifier: String,
    artifact_refs: List(ArtifactType),
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
    misc: dict.Dict(String, List(String)),
  )
}

/// Resolves vendor and indicators for a list of intermediate representations.
@internal
pub fn resolve_intermediate_representations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  irs
  |> list.try_map(fn(ir) {
    use <- bool.guard(
      when: !list.contains(ir.artifact_refs, SLO),
      return: Ok(ir),
    )
    use ir_with_vendor <- result.try(resolve_vendor(ir))
    resolve_indicators(ir_with_vendor)
  })
}

/// Resolves the vendor string to a Vendor type for an intermediate representation.
@internal
pub fn resolve_vendor(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, CompilationError) {
  case ir.values |> list.find(fn(value) { value.label == "vendor" }) {
    Error(_) ->
      Error(errors.SemanticAnalysisVendorResolutionError(
        msg: "expectation '" <> ir_to_identifier(ir) <> "' - no vendor input",
      ))
    Ok(vendor_value_tuple) -> {
      // Safe to assert since already type checked in parser phase.
      let assert Ok(vendor_string) =
        value.extract_string(vendor_value_tuple.value)
      let vendor_value = vendor.resolve_vendor(vendor_string)

      Ok(IntermediateRepresentation(..ir, vendor: option.Some(vendor_value)))
    }
  }
}

/// Resolves indicator templates in an intermediate representation.
@internal
pub fn resolve_indicators(
  ir: IntermediateRepresentation,
) -> Result(IntermediateRepresentation, CompilationError) {
  case ir.vendor {
    option.Some(vendor.Datadog) -> {
      use indicators_value_tuple <- result.try(
        ir.values
        |> list.find(fn(vt) { vt.label == "indicators" })
        |> result.replace_error(errors.SemanticAnalysisTemplateResolutionError(
          msg: "expectation '"
          <> ir_to_identifier(ir)
          <> "' - missing 'indicators' field in IR",
        )),
      )

      use indicators_dict <- result.try(
        value.extract_string_dict(indicators_value_tuple.value)
        |> result.map_error(fn(_) {
          errors.SemanticAnalysisTemplateResolutionError(
            msg: "expectation '"
            <> ir_to_identifier(ir)
            <> "' - failed to decode indicators",
          )
        }),
      )

      let identifier = ir_to_identifier(ir)

      // Resolve all indicators and collect results.
      use resolved_indicators <- result.try(
        indicators_dict
        |> dict.to_list
        |> list.try_map(fn(pair) {
          let #(key, indicator) = pair
          use resolved <- result.map(
            templatizer.parse_and_resolve_query_template(
              indicator,
              ir.values,
              from: identifier,
            ),
          )
          #(key, resolved)
        }),
      )

      // Build the new indicators dict as a Value.
      let resolved_indicators_value =
        resolved_indicators
        |> list.map(fn(pair) { #(pair.0, value.StringValue(pair.1)) })
        |> dict.from_list
        |> value.DictValue

      // Create the new indicators ValueTuple.
      let new_indicators_value_tuple =
        helpers.ValueTuple(
          "indicators",
          CollectionType(Dict(
            PrimitiveType(StringType),
            PrimitiveType(StringType),
          )),
          resolved_indicators_value,
        )

      // Also resolve templates in the "evaluation" field if present.
      let evaluation_tuple_result =
        ir.values
        |> list.find(fn(vt) { vt.label == "evaluation" })

      use resolved_evaluation_tuple <- result.try(case evaluation_tuple_result {
        Error(_) -> Ok(option.None)
        Ok(evaluation_tuple) -> {
          use evaluation_string <- result.try(
            value.extract_string(evaluation_tuple.value)
            |> result.map_error(fn(_) {
              errors.SemanticAnalysisTemplateResolutionError(
                msg: "expectation '"
                <> ir_to_identifier(ir)
                <> "' - failed to decode 'evaluation' field as string",
              )
            }),
          )
          templatizer.parse_and_resolve_query_template(
            evaluation_string,
            ir.values,
            from: identifier,
          )
          |> result.map(fn(resolved_evaluation) {
            option.Some(helpers.ValueTuple(
              "evaluation",
              PrimitiveType(StringType),
              value.StringValue(resolved_evaluation),
            ))
          })
        }
      })

      // Update the IR with the resolved indicators and evaluation.
      let new_values =
        ir.values
        |> list.map(fn(vt) {
          case vt.label {
            "indicators" -> new_indicators_value_tuple
            "evaluation" ->
              case resolved_evaluation_tuple {
                option.Some(new_evaluation) -> new_evaluation
                option.None -> vt
              }
            _ -> vt
          }
        })

      Ok(IntermediateRepresentation(..ir, values: new_values))
    }
    option.Some(vendor.Honeycomb) -> {
      // Honeycomb does not use template resolution — indicators are passed through as-is.
      Ok(ir)
    }
    _ ->
      Error(errors.SemanticAnalysisTemplateResolutionError(
        msg: "expectation '" <> ir_to_identifier(ir) <> "' - no vendor resolved",
      ))
  }
}

/// Build a dotted identifier from IR metadata: org.team.service.name
@internal
pub fn ir_to_identifier(ir: IntermediateRepresentation) -> String {
  ir.metadata.org_name
  <> "."
  <> ir.metadata.team_name
  <> "."
  <> ir.metadata.service_name
  <> "."
  <> ir.metadata.friendly_label
}
