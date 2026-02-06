import caffeine_lang/analysis/dependency_validator
import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ResolvedVendor,
}
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/dependency_graph
import caffeine_lang/codegen/dynatrace
import caffeine_lang/codegen/honeycomb
import caffeine_lang/errors
import caffeine_lang/frontend/pipeline
import caffeine_lang/linker/artifacts
import caffeine_lang/linker/blueprints
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir_builder
import caffeine_lang/linker/linker
import caffeine_lang/source_file.{type SourceFile, SourceFile}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result
import terra_madre/render
import terra_madre/terraform

/// Output of the compilation process containing Terraform, optional dependency graph, and warnings.
pub type CompilationOutput {
  CompilationOutput(
    terraform: String,
    dependency_graph: Option(String),
    warnings: List(String),
  )
}

/// Compiles a blueprint and expectation sources into Terraform configuration.
/// Pure function — all file reading happens before this function is called.
pub fn compile(
  blueprint: SourceFile,
  expectations: List(SourceFile),
) -> Result(CompilationOutput, errors.CompilationError) {
  use irs <- result.try(run_parse_and_link(blueprint, expectations))
  use resolved_irs <- result.try(run_semantic_analysis(irs))
  run_code_generation(resolved_irs)
}

/// Compiles from source strings directly (no file I/O).
/// Used for browser-based compilation.
pub fn compile_from_strings(
  blueprints_source: String,
  expectations_source: String,
  expectations_path: String,
) -> Result(CompilationOutput, errors.CompilationError) {
  use irs <- result.try(parse_from_strings(
    blueprints_source,
    expectations_source,
    expectations_path,
  ))
  use resolved_irs <- result.try(run_semantic_analysis(irs))
  run_code_generation(resolved_irs)
}

// ==== Pipeline stages ====

fn run_parse_and_link(
  blueprint: SourceFile,
  expectations: List(SourceFile),
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  linker.link(blueprint, expectations)
}

fn run_semantic_analysis(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  use validated_irs <- result.try(
    dependency_validator.validate_dependency_relations(irs),
  )
  semantic_analyzer.resolve_intermediate_representations(validated_irs)
}

/// Vendor-specific code generation operations.
type VendorOps {
  VendorOps(
    generate_resources: fn(List(IntermediateRepresentation)) ->
      Result(#(List(terraform.Resource), List(String)), errors.CompilationError),
    terraform_settings: terraform.TerraformSettings,
    provider: terraform.Provider,
    variables: List(terraform.Variable),
  )
}

fn datadog_ops() -> VendorOps {
  VendorOps(
    generate_resources: datadog.generate_resources,
    terraform_settings: datadog.terraform_settings(),
    provider: datadog.provider(),
    variables: datadog.variables(),
  )
}

fn honeycomb_ops() -> VendorOps {
  VendorOps(
    generate_resources: fn(irs) {
      honeycomb.generate_resources(irs)
      |> result.map(fn(r) { #(r, []) })
    },
    terraform_settings: honeycomb.terraform_settings(),
    provider: honeycomb.provider(),
    variables: honeycomb.variables(),
  )
}

fn dynatrace_ops() -> VendorOps {
  VendorOps(
    generate_resources: fn(irs) {
      dynatrace.generate_resources(irs)
      |> result.map(fn(r) { #(r, []) })
    },
    terraform_settings: dynatrace.terraform_settings(),
    provider: dynatrace.provider(),
    variables: dynatrace.variables(),
  )
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(CompilationOutput, errors.CompilationError) {
  let #(datadog_irs, honeycomb_irs, dynatrace_irs) =
    group_by_vendor(resolved_irs)

  // Build vendor groups, defaulting to Datadog boilerplate if no IRs at all.
  let vendor_groups = [
    #(datadog_ops(), datadog_irs),
    #(honeycomb_ops(), honeycomb_irs),
    #(dynatrace_ops(), dynatrace_irs),
  ]
  let active_groups = list.filter(vendor_groups, fn(g) { !list.is_empty(g.1) })
  let active_groups = case list.is_empty(active_groups) {
    True -> [#(datadog_ops(), [])]
    False -> active_groups
  }

  // Generate resources and accumulate config from all active vendors.
  use #(all_resources, all_warnings, required_providers, providers, variables) <- result.try(
    list.try_fold(active_groups, #([], [], [], [], []), fn(acc, group) {
      let #(ops, irs) = group
      let #(resources, warnings, req_provs, provs, vars) = acc
      use #(vendor_resources, vendor_warnings) <- result.try(
        ops.generate_resources(irs),
      )
      Ok(#(
        list.append(resources, vendor_resources),
        list.append(warnings, vendor_warnings),
        list.append(
          req_provs,
          dict.to_list(ops.terraform_settings.required_providers),
        ),
        list.append(provs, [ops.provider]),
        list.append(vars, ops.variables),
      ))
    }),
  )

  let terraform_settings =
    terraform.TerraformSettings(
      required_version: option.None,
      required_providers: dict.from_list(required_providers),
      backend: option.None,
      cloud: option.None,
    )

  let config =
    terraform.Config(
      terraform: option.Some(terraform_settings),
      providers: providers,
      resources: all_resources,
      data_sources: [],
      variables: variables,
      outputs: [],
      locals: [],
      modules: [],
    )

  let terraform_output = render.render_config(config)

  // Dependency graph is only useful when relations exist.
  let has_deps =
    resolved_irs
    |> list.any(fn(ir) {
      list.contains(ir.artifact_refs, artifacts.DependencyRelations)
    })

  let graph = case has_deps {
    True -> option.Some(dependency_graph.generate(resolved_irs))
    False -> option.None
  }

  Ok(CompilationOutput(
    terraform: terraform_output,
    dependency_graph: graph,
    warnings: all_warnings,
  ))
}

/// Group IRs by vendor into (datadog, honeycomb, dynatrace) lists.
fn group_by_vendor(
  irs: List(IntermediateRepresentation),
) -> #(
  List(IntermediateRepresentation),
  List(IntermediateRepresentation),
  List(IntermediateRepresentation),
) {
  let datadog_irs =
    irs
    |> list.filter(fn(ir) { ir.vendor == ResolvedVendor(vendor.Datadog) })
  let honeycomb_irs =
    irs
    |> list.filter(fn(ir) { ir.vendor == ResolvedVendor(vendor.Honeycomb) })
  let dynatrace_irs =
    irs
    |> list.filter(fn(ir) { ir.vendor == ResolvedVendor(vendor.Dynatrace) })
  #(datadog_irs, honeycomb_irs, dynatrace_irs)
}

fn parse_from_strings(
  blueprints_source: String,
  expectations_source: String,
  expectations_path: String,
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  let artifacts = stdlib_artifacts.standard_library()

  use raw_blueprints <- result.try(
    pipeline.compile_blueprints(SourceFile(
      path: "browser/blueprints.caffeine",
      content: blueprints_source,
    )),
  )

  use raw_expectations <- result.try(
    pipeline.compile_expects(SourceFile(
      path: "browser/expectations.caffeine",
      content: expectations_source,
    )),
  )

  use validated_blueprints <- result.try(blueprints.validate_blueprints(
    raw_blueprints,
    artifacts,
  ))

  use expectations_blueprint_collection <- result.try(
    expectations.validate_expectations(
      raw_expectations,
      validated_blueprints,
      from: expectations_path,
    ),
  )

  Ok(
    ir_builder.build_all([
      #(expectations_blueprint_collection, expectations_path),
    ]),
  )
}
