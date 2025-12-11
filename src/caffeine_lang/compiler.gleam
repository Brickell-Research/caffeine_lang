import caffeine_lang/generator/datadog
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/linker
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam_community/ansi

// ==== Print helpers ====

fn print_header() {
  io.println("")
  io.println(ansi.bold(ansi.cyan("=== CAFFEINE COMPILER ===")))
  io.println("")
}

fn print_step1_start(blueprint_path: String, expectations_dir: String) {
  io.println(ansi.bold(ansi.underline("[1/3] Parsing and linking")))
  io.println("  Blueprint file: " <> ansi.dim(blueprint_path))
  io.println("  Expectations directory: " <> ansi.dim(expectations_dir))
}

fn print_step1_success(count: Int) {
  io.println(
    "  " <> ansi.green("✓ Parsed " <> int.to_string(count) <> " expectations"),
  )
}

fn print_step1_error() {
  io.println("  " <> ansi.red("✗ Failed to parse and link"))
}

fn print_step2_start(irs: List(IntermediateRepresentation)) {
  io.println("")
  io.println(ansi.bold(ansi.underline("[2/3] Performing semantic analysis")))
  io.println(
    "  Resolving "
    <> ansi.yellow(int.to_string(list.length(irs)))
    <> " intermediate representations:",
  )
  irs
  |> list.each(fn(ir) {
    io.println(
      "    "
      <> ansi.dim("•")
      <> " "
      <> ir.unique_identifier
      <> " "
      <> ansi.dim("(artifact: " <> ir.artifact_ref <> ")"),
    )
  })
}

fn print_step2_success(count: Int) {
  io.println(
    "  "
    <> ansi.green(
      "✓ Resolved vendors and queries for "
      <> int.to_string(count)
      <> " expectations",
    ),
  )
}

fn print_step2_error() {
  io.println("  " <> ansi.red("✗ Semantic analysis failed"))
}

fn print_step3_start(irs: List(IntermediateRepresentation)) {
  io.println("")
  io.println(ansi.bold(ansi.underline("[3/3] Generating Terraform artifacts")))
  io.println(
    "  Generating resources for "
    <> ansi.yellow(int.to_string(list.length(irs)))
    <> " expectations:",
  )
  irs
  |> list.each(fn(ir) {
    io.println(
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

fn print_step3_success() {
  io.println("  " <> ansi.green("✓ Generated Terraform configuration"))
}

fn print_footer() {
  io.println("")
  io.println(ansi.bold(ansi.green("=== COMPILATION COMPLETE ===")))
  io.println("")
}

// ==== Compiler ====

// TODO: have an actual error type
pub fn compile(
  blueprint_file_path: String,
  expectations_directory: String,
) -> Result(String, String) {
  print_header()

  // Step 1: Parse and Link
  print_step1_start(blueprint_file_path, expectations_directory)
  use irs <- result.try(
    case linker.link(blueprint_file_path, expectations_directory) {
      Error(err) -> {
        print_step1_error()
        Error(err.msg)
      }
      Ok(irs) -> {
        print_step1_success(list.length(irs))
        Ok(irs)
      }
    },
  )

  // Step 2: Semantic Analysis
  print_step2_start(irs)
  use resolved_irs <- result.try(
    case semantic_analyzer.resolve_intermediate_representations(irs) {
      Error(err) -> {
        print_step2_error()
        Error(err.msg)
      }
      Ok(resolved_irs) -> {
        print_step2_success(list.length(resolved_irs))
        Ok(resolved_irs)
      }
    },
  )

  // Step 3: Code Generation
  print_step3_start(resolved_irs)
  let terraform_output = datadog.generate_terraform(resolved_irs)
  print_step3_success()

  print_footer()
  Ok(terraform_output)
}
