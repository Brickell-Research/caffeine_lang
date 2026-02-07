import caffeine_lang/analysis/dependency_validator
import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, NoVendor, ResolvedVendor,
}
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/dependency_graph
import caffeine_lang/codegen/dynatrace
import caffeine_lang/codegen/generator_utils
import caffeine_lang/codegen/honeycomb
import caffeine_lang/codegen/newrelic
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
import gleam/string
import terra_madre/common
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

/// Vendor-specific platform configuration bundling code generation
/// and Terraform boilerplate.
type VendorPlatform {
  VendorPlatform(
    vendor: vendor.Vendor,
    generate_resources: fn(List(IntermediateRepresentation)) ->
      Result(#(List(terraform.Resource), List(String)), errors.CompilationError),
    terraform_settings: terraform.TerraformSettings,
    provider: terraform.Provider,
    variables: List(terraform.Variable),
  )
}

/// Returns the platform configuration for a given vendor.
fn platform_for(v: vendor.Vendor) -> VendorPlatform {
  case v {
    vendor.Datadog ->
      VendorPlatform(
        vendor: vendor.Datadog,
        generate_resources: datadog.generate_resources,
        terraform_settings: datadog.terraform_settings(),
        provider: datadog.provider(),
        variables: datadog.variables(),
      )
    vendor.Honeycomb ->
      VendorPlatform(
        vendor: vendor.Honeycomb,
        generate_resources: fn(irs) {
          honeycomb.generate_resources(irs)
          |> result.map(fn(r) { #(r, []) })
        },
        terraform_settings: honeycomb.terraform_settings(),
        provider: honeycomb.provider(),
        variables: honeycomb.variables(),
      )
    vendor.Dynatrace ->
      VendorPlatform(
        vendor: vendor.Dynatrace,
        generate_resources: fn(irs) {
          dynatrace.generate_resources(irs)
          |> result.map(fn(r) { #(r, []) })
        },
        terraform_settings: dynatrace.terraform_settings(),
        provider: dynatrace.provider(),
        variables: dynatrace.variables(),
      )
    vendor.NewRelic ->
      VendorPlatform(
        vendor: vendor.NewRelic,
        generate_resources: fn(irs) {
          newrelic.generate_resources(irs)
          |> result.map(fn(r) { #(r, []) })
        },
        terraform_settings: newrelic.terraform_settings(),
        provider: newrelic.provider(),
        variables: newrelic.variables(),
      )
  }
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(CompilationOutput, errors.CompilationError) {
  let grouped = group_by_vendor(resolved_irs)

  // Build active platform groups, defaulting to Datadog boilerplate if no IRs.
  let active_groups =
    grouped
    |> dict.to_list
    |> list.map(fn(pair) { #(platform_for(pair.0), pair.1) })
  let active_groups = case list.is_empty(active_groups) {
    True -> [#(platform_for(vendor.Datadog), [])]
    False -> active_groups
  }

  // Generate resources and accumulate config from all active vendors.
  // Note: active_groups has at most 4 elements (one per vendor), so the
  // list.append calls here are bounded and not a performance concern.
  use #(all_resources, all_warnings, required_providers, providers, variables) <- result.try(
    list.try_fold(active_groups, #([], [], [], [], []), fn(acc, group) {
      let #(platform, irs) = group
      let #(resources, warnings, req_provs, provs, vars) = acc
      use #(vendor_resources, vendor_warnings) <- result.try(
        platform.generate_resources(irs),
      )
      Ok(#(
        list.append(resources, vendor_resources),
        list.append(warnings, vendor_warnings),
        list.append(
          req_provs,
          dict.to_list(platform.terraform_settings.required_providers),
        ),
        list.append(provs, [platform.provider]),
        list.append(vars, platform.variables),
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

  // Render boilerplate (terraform/provider/variable blocks) without resources.
  let boilerplate_config =
    terraform.Config(
      terraform: option.Some(terraform_settings),
      providers: providers,
      resources: [],
      data_sources: [],
      variables: variables,
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

/// Groups IRs by their resolved vendor, preserving input order within each group.
fn group_by_vendor(
  irs: List(IntermediateRepresentation),
) -> dict.Dict(vendor.Vendor, List(IntermediateRepresentation)) {
  list.group(irs, fn(ir) {
    case ir.vendor {
      ResolvedVendor(v) -> v
      // Non-SLO IRs default to Datadog for boilerplate.
      NoVendor -> vendor.Datadog
    }
  })
  |> dict.map_values(fn(_, group) { list.reverse(group) })
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
