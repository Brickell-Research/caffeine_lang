import caffeine_lang/analysis/dependency_validator
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/dependency_graph
import caffeine_lang/codegen/generator_utils
import caffeine_lang/codegen/platforms
import caffeine_lang/codegen/relay
import caffeine_lang/errors
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir.{
  type DepsValidated, type IntermediateRepresentation, type Linked,
  type Resolved,
}
import caffeine_lang/linker/ir_builder
import caffeine_lang/linker/linker
import caffeine_lang/linker/measurements
import caffeine_lang/source_file.{
  type ExpectationSource, type SourceFile, type VendorMeasurementSource,
  SourceFile,
}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import terra_madre/common
import terra_madre/render
import terra_madre/terraform

/// Output of the compilation process. Includes Terraform (always), the
/// dependency graph when relations exist, the relay's `signals.json` when
/// any expectation uses external-signal indicators, and any warnings the
/// codegen accumulated.
pub type CompilationOutput {
  CompilationOutput(
    terraform: String,
    dependency_graph: Option(String),
    relay_signals: Option(String),
    warnings: List(String),
  )
}

/// Compiles measurement sources and expectation sources into Terraform configuration.
/// Pure function — all file reading happens before this function is called.
pub fn compile(
  measurements: List(VendorMeasurementSource),
  expectations: List(SourceFile(ExpectationSource)),
) -> Result(CompilationOutput, errors.CompilationError) {
  use irs <- result.try(run_parse_and_link(measurements, expectations))
  use resolved_irs <- result.try(run_semantic_analysis(irs))
  run_code_generation(resolved_irs)
}

/// Compiles from source strings directly (no file I/O).
/// Used for browser-based compilation. The vendor parameter specifies
/// which vendor the measurements belong to.
pub fn compile_from_strings(
  measurements_source: String,
  expectations_source: String,
  expectations_path: String,
  vendor vendor_string: String,
) -> Result(CompilationOutput, errors.CompilationError) {
  use irs <- result.try(parse_from_strings(
    measurements_source,
    expectations_source,
    expectations_path,
    vendor_string,
  ))
  use resolved_irs <- result.try(run_semantic_analysis(irs))
  run_code_generation(resolved_irs)
}

// ==== Pipeline stages ====

fn run_parse_and_link(
  measurements: List(VendorMeasurementSource),
  expectations: List(SourceFile(ExpectationSource)),
) -> Result(List(IntermediateRepresentation(Linked)), errors.CompilationError) {
  let slo_params = stdlib_artifacts.slo_params()
  linker.link(measurements, expectations, slo_params:)
}

fn run_semantic_analysis(
  irs: List(IntermediateRepresentation(Linked)),
) -> Result(List(IntermediateRepresentation(Resolved)), errors.CompilationError) {
  use validated_irs <- result.try(
    dependency_validator.validate_dependency_relations(irs),
  )
  validated_irs
  |> list.map(resolve_indicators)
  |> errors.from_results()
}

/// Vendor dispatch for indicator template resolution. Datadog uses template
/// substitution; unmeasured IRs (vendor = None) pass through unchanged.
@internal
pub fn resolve_indicators(
  ir: IntermediateRepresentation(DepsValidated),
) -> Result(IntermediateRepresentation(Resolved), errors.CompilationError) {
  case ir.vendor {
    option.Some(vendor.Datadog) -> datadog.resolve_indicators(ir)
    option.None -> Ok(ir.promote(ir))
  }
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation(Resolved)),
) -> Result(CompilationOutput, errors.CompilationError) {
  // Filter out unmeasured IRs (vendor = None) before codegen.
  // Unmeasured IRs participate in dependency graphs but not Terraform generation.
  // Sort by unique_identifier for deterministic output.
  let measured_irs =
    resolved_irs
    |> list.filter(fn(ir) { option.is_some(ir.vendor) })
    |> list.sort(fn(a, b) {
      string.compare(a.unique_identifier, b.unique_identifier)
    })

  // Datadog is the only platform today. Multi-vendor dispatch will return
  // when a second `Platform` is added.
  let platform = platforms.datadog_platform()
  use #(all_resources, all_warnings) <- result.try(platform.generate_resources(
    measured_irs,
  ))

  let terraform_settings = platforms.terraform_settings(platform)

  // Render boilerplate (terraform/provider/variable blocks) without resources.
  let boilerplate_config =
    terraform.Config(
      terraform: option.Some(terraform_settings),
      providers: [platforms.provider(platform)],
      resources: [],
      data_sources: [],
      variables: platform.variables,
      outputs: [],
      locals: [],
      modules: [],
    )
  let boilerplate = render.render_config(boilerplate_config)

  // Build resource name → metadata lookup for source comments.
  let metadata_by_name =
    resolved_irs
    |> list.flat_map(fn(ir) {
      let base = common.sanitize_terraform_identifier(ir.unique_identifier)
      [#(base, ir.metadata), #(base <> "_sli", ir.metadata)]
    })
    |> dict.from_list

  // Render each resource with a source traceability comment.
  let resource_sections =
    all_resources
    |> list.map(fn(resource) {
      let rendered = generator_utils.render_resource_to_string(resource)
      case dict.get(metadata_by_name, resource.name) {
        Ok(metadata) ->
          generator_utils.build_source_comment(metadata) <> "\n" <> rendered
        Error(_) -> rendered
      }
    })

  // Assemble final output: boilerplate + commented resources.
  let terraform_output = case resource_sections {
    [] -> boilerplate
    sections -> {
      let trimmed_boilerplate = string.drop_end(boilerplate, 1)
      trimmed_boilerplate <> "\n\n" <> string.join(sections, "\n\n") <> "\n"
    }
  }

  // Dependency graph is only useful when relations exist.
  let has_deps =
    resolved_irs
    |> list.any(fn(ir) { option.is_some(ir.slo.depends_on) })

  let graph = case has_deps {
    True -> option.Some(dependency_graph.generate(resolved_irs))
    False -> option.None
  }

  // Relay routing table (`signals.json`) is emitted only when at least one
  // expectation uses an external-signal indicator. Pure literal-query
  // pipelines need no relay and skip this artifact.
  let relay_signals = relay.generate(resolved_irs)

  Ok(CompilationOutput(
    terraform: terraform_output,
    dependency_graph: graph,
    relay_signals: relay_signals,
    warnings: all_warnings,
  ))
}

fn parse_from_strings(
  measurements_source: String,
  expectations_source: String,
  expectations_path: String,
  vendor_string: String,
) -> Result(List(IntermediateRepresentation(Linked)), errors.CompilationError) {
  let slo_params = stdlib_artifacts.slo_params()
  let reserved_labels = ir_builder.reserved_labels(slo_params)

  use resolved_vendor <- result.try(
    vendor.resolve_vendor(vendor_string)
    |> result.replace_error(errors.linker_vendor_resolution_error(
      msg: "unknown vendor '" <> vendor_string <> "'",
    )),
  )

  use raw_measurements <- result.try(
    pipeline.compile_measurements(SourceFile(
      path: "browser/measurements.caffeine",
      content: measurements_source,
    )),
  )

  use raw_expectations <- result.try(
    pipeline.compile_expects(SourceFile(
      path: "browser/expectations.caffeine",
      content: expectations_source,
    )),
  )

  use validated_measurements <- result.try(measurements.validate_measurements(
    raw_measurements,
    slo_params,
  ))

  let vendor_lookup =
    raw_measurements
    |> list.map(fn(bp) { #(bp.name, resolved_vendor) })
    |> dict.from_list

  use expectations_measurement_collection <- result.try(
    expectations.validate_expectations(
      raw_expectations,
      validated_measurements,
      slo_params: slo_params,
      from: expectations_path,
    ),
  )

  ir_builder.build_all(
    [#(expectations_measurement_collection, expectations_path)],
    reserved_labels:,
    vendor_lookup:,
    slo_params:,
  )
}
