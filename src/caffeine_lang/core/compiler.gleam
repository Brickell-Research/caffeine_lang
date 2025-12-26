import caffeine_lang/common/errors
import caffeine_lang/core/compilation_configuration.{type CompilationConfig}
import caffeine_lang/core/logger
import caffeine_lang/generator/datadog
import caffeine_lang/middle_end/ir_builder
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/artifacts
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/linker
import gleam/int
import gleam/list
import gleam/result
import gleam_community/ansi

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
  expectations_dir: String,
) {
  logger.log(
    config.log_level,
    ansi.bold(ansi.underline("[1/3] Parsing and linking")),
  )
  logger.log(config.log_level, "  Blueprint file: " <> ansi.dim(blueprint_path))
  logger.log(
    config.log_level,
    "  Expectations directory: " <> ansi.dim(expectations_dir),
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
        <> ansi.dim("(artifact: " <> ir.artifact_ref <> ")"),
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
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  linker.link(blueprint_file_path, expectations_directory)
}

fn run_semantic_analysis(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  semantic_analyzer.resolve_intermediate_representations(irs)
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(String, errors.CompilationError) {
  datadog.generate_terraform(resolved_irs)
}

// ==== Compiler ====
pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
  config: CompilationConfig,
) -> Result(String, errors.CompilationError) {
  print_header(config)

  // Step 1: Parse and Link
  print_step1_start(config, blueprint_file_path, expectations_directory)
  use irs <- result.try(
    case run_parse_and_link(blueprint_file_path, expectations_directory) {
      Error(err) -> {
        print_step1_error(config)
        Error(err)
      }
      Ok(irs) -> {
        print_step1_success(config, list.length(irs))
        Ok(irs)
      }
    },
  )

  // Step 2: Semantic Analysis
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

  // Step 3: Code Generation
  print_step3_start(config, resolved_irs)
  use terraform_output <- result.try(case run_code_generation(resolved_irs) {
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
  Ok(terraform_output)
}

/// Compile from JSON strings directly (no file I/O).
/// Used for browser-based compilation.
pub fn compile_from_strings(
  blueprints_json: String,
  expectations_json: String,
  expectations_path: String,
) -> Result(String, errors.CompilationError) {
  // Step 1: Parse (no file I/O)
  use irs <- result.try(parse_from_strings(
    blueprints_json,
    expectations_json,
    expectations_path,
  ))

  // Step 2: Semantic analysis
  use resolved_irs <- result.try(run_semantic_analysis(irs))

  // Step 3: Code generation
  run_code_generation(resolved_irs)
}

fn parse_from_strings(
  blueprints_json: String,
  expectations_json: String,
  expectations_path: String,
) -> Result(List(IntermediateRepresentation), errors.CompilationError) {
  use artifacts <- result.try(artifacts.parse_standard_library())

  use validated_blueprints <- result.try(
    blueprints.parse_from_json_string(blueprints_json, artifacts),
  )

  use expectations_blueprint_collection <- result.try(
    expectations.parse_from_json_string(expectations_json, validated_blueprints),
  )

  Ok(ir_builder.build_all([#(expectations_blueprint_collection, expectations_path)]))
}
