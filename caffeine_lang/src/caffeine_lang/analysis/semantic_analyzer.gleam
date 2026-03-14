/// Semantic analysis phase: resolves indicators for intermediate representations.
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/linker/ir.{
  type DepsValidated, type IntermediateRepresentation, type Resolved,
}
import gleam/bool
import gleam/list
import gleam/option

/// Resolves indicators for a list of intermediate representations.
/// Accumulates errors from all IRs instead of stopping at the first failure.
@internal
pub fn resolve_intermediate_representations(
  irs: List(IntermediateRepresentation(DepsValidated)),
) -> Result(List(IntermediateRepresentation(Resolved)), CompilationError) {
  irs
  |> list.map(fn(ir) {
    use <- bool.guard(
      when: !list.contains(ir.artifact_refs, SLO),
      return: Ok(ir.promote(ir)),
    )
    resolve_indicators(ir)
  })
  |> errors.from_results()
}

/// Resolves indicator templates in an intermediate representation.
/// Dispatches to vendor-specific resolution; only Datadog uses template resolution.
@internal
pub fn resolve_indicators(
  ir: IntermediateRepresentation(DepsValidated),
) -> Result(IntermediateRepresentation(Resolved), CompilationError) {
  case ir.vendor {
    option.Some(vendor.Datadog) -> datadog.resolve_indicators(ir)
    option.Some(vendor.Honeycomb)
    | option.Some(vendor.Dynatrace)
    | option.Some(vendor.NewRelic) -> Ok(ir.promote(ir))
    option.None ->
      Error(errors.semantic_analysis_template_resolution_error(
        msg: "expectation '"
        <> ir.ir_to_identifier(ir)
        <> "' - no vendor resolved",
      ))
  }
}
