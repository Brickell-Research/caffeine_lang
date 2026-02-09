/// Semantic analysis phase: resolves indicators for intermediate representations.
import caffeine_lang/analysis/templatizer
import caffeine_lang/analysis/vendor
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, IntermediateRepresentation, SloFields,
}
import caffeine_lang/types.{
  CollectionType, Dict, PrimitiveType, String as StringType,
}
import caffeine_lang/value
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option
import gleam/result

/// Resolves indicators for a list of intermediate representations.
/// Accumulates errors from all IRs instead of stopping at the first failure.
@internal
pub fn resolve_intermediate_representations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  irs
  |> list.map(fn(ir) {
    use <- bool.guard(
      when: !list.contains(ir.artifact_refs, SLO),
      return: Ok(ir),
    )
    resolve_indicators(ir)
  })
  |> errors.from_results()
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
            <> ir.ir_to_identifier(ir)
            <> "' - missing 'indicators' field in IR",
          context: errors.empty_context(),
        )),
      )

      use indicators_dict <- result.try(
        value.extract_string_dict(indicators_value_tuple.value)
        |> result.map_error(fn(_) {
          errors.SemanticAnalysisTemplateResolutionError(
            msg: "expectation '"
              <> ir.ir_to_identifier(ir)
              <> "' - failed to decode indicators",
            context: errors.empty_context(),
          )
        }),
      )

      let identifier = ir.ir_to_identifier(ir)

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
                  <> ir.ir_to_identifier(ir)
                  <> "' - failed to decode 'evaluation' field as string",
                context: errors.empty_context(),
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

      // Also update the structured artifact_data with resolved values.
      let resolved_indicators_dict = resolved_indicators |> dict.from_list
      let resolved_eval = case resolved_evaluation_tuple {
        option.Some(vt) -> value.extract_string(vt.value) |> option.from_result
        option.None ->
          ir.get_slo_fields(ir.artifact_data)
          |> option.map(fn(slo) { slo.evaluation })
          |> option.unwrap(option.None)
      }
      let new_artifact_data =
        ir.update_slo_fields(ir.artifact_data, fn(slo) {
          SloFields(
            ..slo,
            indicators: resolved_indicators_dict,
            evaluation: resolved_eval,
          )
        })

      Ok(
        IntermediateRepresentation(
          ..ir,
          values: new_values,
          artifact_data: new_artifact_data,
        ),
      )
    }
    option.Some(vendor.Honeycomb) -> {
      // Honeycomb does not use template resolution — indicators are passed through as-is.
      Ok(ir)
    }
    option.Some(vendor.Dynatrace) -> {
      // Dynatrace does not use template resolution — indicators are passed through as-is.
      Ok(ir)
    }
    option.Some(vendor.NewRelic) -> {
      // New Relic does not use template resolution — indicators are passed through as-is.
      Ok(ir)
    }
    option.None ->
      Error(errors.SemanticAnalysisTemplateResolutionError(
        msg: "expectation '"
          <> ir.ir_to_identifier(ir)
          <> "' - no vendor resolved",
        context: errors.empty_context(),
      ))
  }
}
