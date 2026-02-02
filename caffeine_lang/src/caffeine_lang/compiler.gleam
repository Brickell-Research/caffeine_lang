import caffeine_lang/analysis/dependency_validator
import caffeine_lang/analysis/semantic_analyzer.{type IntermediateRepresentation}
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/dependency_graph
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

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(CompilationOutput, errors.CompilationError) {
  let #(datadog_irs, honeycomb_irs) = group_by_vendor(resolved_irs)

  let has_datadog = !list.is_empty(datadog_irs)
  let has_honeycomb = !list.is_empty(honeycomb_irs)

  // If no IRs at all, default to Datadog boilerplate (backwards compat).
  let has_datadog = has_datadog || !has_honeycomb

  // Generate resources per vendor.
  use #(datadog_resources, datadog_warnings) <- result.try(case has_datadog {
    True -> datadog.generate_resources(datadog_irs)
    False -> Ok(#([], []))
  })

  use honeycomb_resources <- result.try(case has_honeycomb {
    True -> honeycomb.generate_resources(honeycomb_irs)
    False -> Ok([])
  })

  // Merge terraform settings (required_providers from each vendor).
  let required_providers =
    []
    |> list.append(case has_datadog {
      True -> dict.to_list(datadog.terraform_settings().required_providers)
      False -> []
    })
    |> list.append(case has_honeycomb {
      True -> dict.to_list(honeycomb.terraform_settings().required_providers)
      False -> []
    })
    |> dict.from_list

  let terraform_settings =
    terraform.TerraformSettings(
      required_version: option.None,
      required_providers: required_providers,
      backend: option.None,
      cloud: option.None,
    )

  // Collect providers and variables for used vendors only.
  let providers =
    []
    |> list.append(case has_datadog {
      True -> [datadog.provider()]
      False -> []
    })
    |> list.append(case has_honeycomb {
      True -> [honeycomb.provider()]
      False -> []
    })

  let variables =
    []
    |> list.append(case has_datadog {
      True -> datadog.variables()
      False -> []
    })
    |> list.append(case has_honeycomb {
      True -> honeycomb.variables()
      False -> []
    })

  let config =
    terraform.Config(
      terraform: option.Some(terraform_settings),
      providers: providers,
      resources: list.append(datadog_resources, honeycomb_resources),
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
    warnings: datadog_warnings,
  ))
}

/// Group IRs by vendor into (datadog, honeycomb) lists.
fn group_by_vendor(
  irs: List(IntermediateRepresentation),
) -> #(List(IntermediateRepresentation), List(IntermediateRepresentation)) {
  let datadog_irs =
    irs
    |> list.filter(fn(ir) { ir.vendor == option.Some(vendor.Datadog) })
  let honeycomb_irs =
    irs
    |> list.filter(fn(ir) { ir.vendor == option.Some(vendor.Honeycomb) })
  #(datadog_irs, honeycomb_irs)
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
