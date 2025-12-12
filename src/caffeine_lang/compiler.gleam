import caffeine_lang/generator/datadog
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/artifacts
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/linker
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam_community/ansi

// ==== Configuration ====

pub type LogLevel {
  Verbose
  Minimal
}

pub type CompilationConfig {
  CompilationConfig(log_level: LogLevel)
}

// ==== Print helpers ====

fn log(config: CompilationConfig, message: String) {
  case config.log_level {
    Verbose -> io.println(message)
    Minimal -> Nil
  }
}

fn print_header(config: CompilationConfig) {
  log(config, "")
  log(config, ansi.bold(ansi.cyan("=== CAFFEINE COMPILER ===")))
  log(config, "")
}

fn print_step1_start(
  config: CompilationConfig,
  blueprint_path: String,
  expectations_dir: String,
) {
  log(config, ansi.bold(ansi.underline("[1/3] Parsing and linking")))
  log(config, "  Blueprint file: " <> ansi.dim(blueprint_path))
  log(config, "  Expectations directory: " <> ansi.dim(expectations_dir))
}

fn print_step1_success(config: CompilationConfig, count: Int) {
  log(
    config,
    "  " <> ansi.green("✓ Parsed " <> int.to_string(count) <> " expectations"),
  )
}

fn print_step1_error(config: CompilationConfig) {
  log(config, "  " <> ansi.red("✗ Failed to parse and link"))
}

fn print_step2_start(
  config: CompilationConfig,
  irs: List(IntermediateRepresentation),
) {
  log(config, "")
  log(config, ansi.bold(ansi.underline("[2/3] Performing semantic analysis")))
  log(
    config,
    "  Resolving "
      <> ansi.yellow(int.to_string(list.length(irs)))
      <> " intermediate representations:",
  )
  irs
  |> list.each(fn(ir) {
    log(
      config,
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
  log(
    config,
    "  "
      <> ansi.green(
        "✓ Resolved vendors and queries for "
        <> int.to_string(count)
        <> " expectations",
      ),
  )
}

fn print_step2_error(config: CompilationConfig) {
  log(config, "  " <> ansi.red("✗ Semantic analysis failed"))
}

fn print_step3_start(
  config: CompilationConfig,
  irs: List(IntermediateRepresentation),
) {
  log(config, "")
  log(
    config,
    ansi.bold(ansi.underline("[3/3] Generating Terraform artifacts")),
  )
  log(
    config,
    "  Generating resources for "
      <> ansi.yellow(int.to_string(list.length(irs)))
      <> " expectations:",
  )
  irs
  |> list.each(fn(ir) {
    log(
      config,
      "    "
        <> ansi.dim("•")
        <> " "
        <> ir.metadata.friendly_label
        <> " "
        <> ansi.dim(
          "(org: "
          <> ir.metadata.org_name
          <> ", service: "
          <> ir.metadata.service_name
          <> ")",
        ),
    )
  })
}

fn print_step3_success(config: CompilationConfig) {
  log(config, "  " <> ansi.green("✓ Generated Terraform configuration"))
}

fn print_step3_error(config: CompilationConfig) {
  log(config, "  " <> ansi.red("✗ Code generation failed"))
}

fn print_footer(config: CompilationConfig) {
  log(config, "")
  log(config, ansi.bold(ansi.green("=== COMPILATION COMPLETE ===")))
  log(config, "")
}

// ==== Shared compilation steps ====
fn run_semantic_analysis(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), String) {
  semantic_analyzer.resolve_intermediate_representations(irs)
  |> result.map_error(fn(err) { "Semantic analysis error: " <> err.msg })
}

fn run_code_generation(
  resolved_irs: List(IntermediateRepresentation),
) -> Result(String, String) {
  datadog.generate_terraform(resolved_irs)
  |> result.map_error(fn(err) { "Code generation error: " <> err.msg })
}

// ==== Compiler ====

// TODO: have an actual error type
pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
  config: CompilationConfig,
) -> Result(String, String) {
  print_header(config)

  // Step 1: Parse and Link
  print_step1_start(config, blueprint_file_path, expectations_directory)
  use irs <- result.try(
    case linker.link(blueprint_file_path, expectations_directory) {
      Error(err) -> {
        print_step1_error(config)
        Error(err.msg)
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
) -> Result(String, String) {
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
) -> Result(List(IntermediateRepresentation), String) {
  use artifacts <- result.try(
    artifacts.parse_standard_library()
    |> result.map_error(fn(err) { "Artifact error: " <> err.msg }),
  )

  use validated_blueprints <- result.try(
    blueprints.parse_from_string(blueprints_json, artifacts)
    |> result.map_error(fn(err) { "Blueprint error: " <> err.msg }),
  )

  expectations.parse_from_string(
    expectations_json,
    expectations_path,
    validated_blueprints,
  )
  |> result.map_error(fn(err) { "Expectation error: " <> err.msg })
}
