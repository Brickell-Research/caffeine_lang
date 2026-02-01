import caffeine_lang/common/errors
import caffeine_lang/common/source_file.{type SourceFile, SourceFile}
import caffeine_lang/core/compilation_configuration.{type CompilationConfig}
import caffeine_lang/core/logger
import caffeine_lang/frontend/pipeline
import caffeine_lang/generator/datadog
import caffeine_lang/generator/dependency_graph
import caffeine_lang/generator/honeycomb
import caffeine_lang/middle_end/dependency_validator
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/middle_end/vendor
import caffeine_lang/parser/artifacts
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/ir_builder
import caffeine_lang/parser/linker
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam_community/ansi
import terra_madre/render
import terra_madre/terraform

/// Output of the compilation process containing Terraform and optional dependency graph.
pub type CompilationOutput {
  CompilationOutput(terraform: String, dependency_graph: Option(String))
}

/// Compiles a blueprint and expectation sources into Terraform configuration.
/// All file reading happens before this function is called.
pub fn compile(
  blueprint: SourceFile,
  expectations: List(SourceFile),
  config: CompilationConfig,
) -> Result(CompilationOutput, errors.CompilationError) {
  print_header(config)

  // Step 1: Parse and Link.
  print_step1_start(config, blueprint.path, expectations)
  use irs <- result.try(case run_parse_and_link(blueprint, expectations) {
    Error(err) -> {
      print_step1_error(config)
      Error(err)
    }
    Ok(irs) -> {
      print_step1_success(config, list.length(irs))
      Ok(irs)
    }
  })

  // Step 2: Semantic Analysis.
  print_step2_start(config, irs)
  use resolved_irs <- result.try(case run_semantic_analysis(irs) {
    Error(err) -> {
      print_step2_error(config)
      Error(err)
    }
    Ok(resolved_irs) -> {
      print_step2_success(config, list.length(resolved_irs))
      Ok(resolved_irs)
    }
  })

  // Step 3: Code Generation.
  print_step3_start(config, resolved_irs)
  use output <- result.try(case run_code_generation(resolved_irs) {
    Error(err) -> {
      print_step3_error(config)
      Error(err)
    }
    Ok(output) -> {
      print_step3_success(config)
      Ok(output)
    }
  })

  print_footer(config)
  Ok(output)
}

/// Compiles from JSON strings directly (no file I/O).
/// Used for browser-based compilation.
pub fn compile_from_strings(
  blueprints_json: String,
  expectations_json: String,
  expectations_path: String,
) -> Result(CompilationOutput, errors.CompilationError) {
  // Step 1: Parse (no file I/O).
  use irs <- result.try(parse_from_strings(
    blueprints_json,
    expectations_json,
    expectations_path,
  ))

  // Step 2: Semantic analysis.
  use resolved_irs <- result.try(run_semantic_analysis(irs))

  // Step 3: Code generation.
  run_code_generation(resolved_irs)
}

// ==== Print helpers ====

fn print_header(config: CompilationConfig) {
  logger.log(config.log_level, "")
  logger.log(
    config.log_level,
    ansi.bold(ansi.cyan("=== CAFFEINE COMPILER ===")),
  )
  logger.log(config.log_level, "")
}

fn print_step1_start(
  config: CompilationConfig,
  blueprint_path: String,
  expectations: List(SourceFile),
) {
  logger.log(
    config.log_level,
    ansi.bold(ansi.underline("[1/3] Parsing and linking")),
  )
  logger.log(config.log_level, "  Blueprint file: " <> ansi.dim(blueprint_path))
  logger.log(
    config.log_level,
    "  Expectation files: "
      <> ansi.dim(int.to_string(list.length(expectations))),
  )
}

fn print_step1_success(config: CompilationConfig, count: Int) {
  logger.log(
    config.log_level,
    "  " <> ansi.green("✓ Parsed " <> int.to_string(count) <> " expectations"),
  )
}

fn print_step1_error(config: CompilationConfig) {
  logger.log(config.log_level, "  " <> ansi.red("✗ Failed to parse and link"))
}

fn print_step2_start(
  config: CompilationConfig,
  irs: List(IntermediateRepresentation),
) {
  logger.log(config.log_level, "")
  logger.log(
    config.log_level,
    ansi.bold(ansi.underline("[2/3] Performing semantic analysis")),
  )
  logger.log(
    config.log_level,
    "  Resolving "
      <> ansi.yellow(int.to_string(list.length(irs)))
      <> " intermediate representations:",
  )
  irs
  |> list.each(fn(ir) {
    logger.log(
      config.log_level,
      "    "
        <> ansi.dim("•")
        <> " "
        <> ir.unique_identifier
        <> " "
        <> ansi.dim(
        "(artifacts: " <> string.join(ir.artifact_refs, ", ") <> ")",
      ),
    )
  })
}

fn print_step2_success(config: CompilationConfig, count: Int) {
  logger.log(
    config.log_level,
    "  "
      <> ansi.green(
      "✓ Resolved vendors and queries for "
      <> int.to_string(count)
      <> " expectations",
    ),
  )
}

fn print_step2_error(config: CompilationConfig) {
  logger.log(config.log_level, "  " <> ansi.red("✗ Semantic analysis failed"))
}

fn print_step3_start(
  config: CompilationConfig,
  irs: List(IntermediateRepresentation),
) {
  logger.log(config.log_level, "")
  logger.log(
    config.log_level,
    ansi.bold(ansi.underline("[3/3] Generating Terraform artifacts")),
  )
  logger.log(
    config.log_level,
    "  Generating resources for "
      <> ansi.yellow(int.to_string(list.length(irs)))
      <> " expectations:",
  )
  irs
  |> list.each(fn(ir) {
    logger.log(
      config.log_level,
      "    "
        <> ansi.dim("•")
        <> " "
        <> ir.metadata.friendly_label
        <> " "
        <> ansi.dim(
        "(org: "
        <> ir.metadata.org_name
        <> ", team: "
        <> ir.metadata.team_name
        <> ", service: "
        <> ir.metadata.service_name
        <> ")",
      ),
    )
  })
}

fn print_step3_success(config: CompilationConfig) {
  logger.log(
    config.log_level,
    "  " <> ansi.green("✓ Generated Terraform configuration"),
  )
}

fn print_step3_error(config: CompilationConfig) {
  logger.log(config.log_level, "  " <> ansi.red("✗ Code generation failed"))
}

fn print_footer(config: CompilationConfig) {
  logger.log(config.log_level, "")
  logger.log(
    config.log_level,
    ansi.bold(ansi.green("=== COMPILATION COMPLETE ===")),
  )
  logger.log(config.log_level, "")
}

// ==== Shared compilation steps ====

fn run_parse_and_link(
  blueprint: SourceFile,
  expectations: List(SourceFile),
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  linker.link(blueprint, expectations)
}

fn run_semantic_analysis(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  // First validate dependency relations (if any)
  use validated_irs <- result.try(
    dependency_validator.validate_dependency_relations(irs),
  )
  // Then resolve vendors and queries
  semantic_analyzer.resolve_intermediate_representations(validated_irs)
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(CompilationOutput, errors.CompilationError) {
  // Group IRs by vendor, generate resources per vendor, merge into one config.
  let #(datadog_irs, honeycomb_irs) = group_by_vendor(resolved_irs)

  let has_datadog = !list.is_empty(datadog_irs)
  let has_honeycomb = !list.is_empty(honeycomb_irs)

  // If no IRs at all, default to Datadog boilerplate (backwards compat).
  let has_datadog = has_datadog || !has_honeycomb

  // Generate resources per vendor.
  use datadog_resources <- result.try(case has_datadog {
    True -> datadog.generate_resources(datadog_irs)
    False -> Ok([])
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

  // Generate dependency graph if any IRs have DependencyRelations
  let has_deps =
    resolved_irs
    |> list.any(fn(ir) {
      list.contains(ir.artifact_refs, "DependencyRelations")
    })

  let graph = case has_deps {
    True -> option.Some(dependency_graph.generate(resolved_irs))
    False -> option.None
  }

  Ok(CompilationOutput(terraform: terraform_output, dependency_graph: graph))
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
  // Run the DSL frontend pipeline to produce JSON
  use blueprints_json <- result.try(
    pipeline.compile_blueprints(SourceFile(
      path: "browser/blueprints.caffeine",
      content: blueprints_source,
    )),
  )

  use expectations_json <- result.try(
    pipeline.compile_expects(SourceFile(
      path: "browser/expectations.caffeine",
      content: expectations_source,
    )),
  )

  // Parse the generated JSON
  use artifacts <- result.try(artifacts.parse_standard_library())

  use validated_blueprints <- result.try(blueprints.parse_from_json_string(
    blueprints_json,
    artifacts,
  ))

  use expectations_blueprint_collection <- result.try(
    expectations.parse_from_json_string(
      expectations_json,
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
