import caffeine_cli/color
import caffeine_cli/compile_presenter.{type LogLevel}
import caffeine_cli/display
import caffeine_cli/error_presenter
import caffeine_cli/file_discovery
import caffeine_lang/compiler.{type CompilationOutput}
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/frontend/formatter
import caffeine_lang/rich_error
import caffeine_lang/source_file.{SourceFile}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import filepath
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import glint
import glint/constraint
import simplifile

// --- Flag definitions ---

fn quiet_flag() -> glint.Flag(Bool) {
  glint.bool_flag("quiet")
  |> glint.flag_default(False)
  |> glint.flag_help("Suppress compilation progress output")
}

fn check_flag() -> glint.Flag(Bool) {
  glint.bool_flag("check")
  |> glint.flag_default(False)
  |> glint.flag_help("Check formatting without modifying files")
}

fn target_flag() -> glint.Flag(String) {
  glint.string_flag("target")
  |> glint.flag_default("terraform")
  |> glint.flag_help("Code generation target: terraform or opentofu")
  |> glint.flag_constraint(constraint.one_of(["terraform", "opentofu"]))
}

// --- Version ---

/// Returns the version string for `--version` output.
pub fn version_string() -> String {
  "caffeine " <> constants.version <> " (Brickell Research)"
}

// --- Log level helper ---

fn log_level_from_quiet(quiet: Bool) -> LogLevel {
  case quiet {
    True -> compile_presenter.Minimal
    False -> compile_presenter.Verbose
  }
}

// --- Command builders ---

/// Builds the compile subcommand.
@internal
pub fn compile_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help(
    "Compile .caffeine blueprints and expectations to output",
  )
  use quiet <- glint.flag(quiet_flag())
  use target <- glint.flag(target_flag())
  use blueprint_file <- glint.named_arg("blueprint_file")
  use expectations_dir <- glint.named_arg("expectations_dir")
  use <- glint.unnamed_args(glint.MinArgs(0))
  use named, unnamed_args, flags <- glint.command()

  let assert Ok(is_quiet) = quiet(flags)
  let assert Ok(target) = target(flags)
  let log_level = log_level_from_quiet(is_quiet)
  let bp = blueprint_file(named)
  let exp_dir = expectations_dir(named)
  let output_path = case unnamed_args {
    [path, ..] -> option.Some(path)
    [] -> option.None
  }

  compile(bp, exp_dir, output_path, target, log_level)
}

/// Builds the format subcommand.
@internal
pub fn format_command_builder() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help("Format .caffeine files")
  use quiet <- glint.flag(quiet_flag())
  use check <- glint.flag(check_flag())
  use path <- glint.named_arg("path")
  use named, _, flags <- glint.command()

  let assert Ok(is_quiet) = quiet(flags)
  let assert Ok(check_only) = check(flags)
  let log_level = log_level_from_quiet(is_quiet)

  format_command(path(named), check_only, log_level)
}

/// Builds the artifacts subcommand.
@internal
pub fn artifacts_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help(
    "List available artifacts from the standard library",
  )
  use quiet <- glint.flag(quiet_flag())
  use _, _, flags <- glint.command()

  let assert Ok(is_quiet) = quiet(flags)
  artifacts_catalog(log_level_from_quiet(is_quiet))
}

/// Builds the types subcommand.
@internal
pub fn types_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help(
    "Show the type system reference with all supported types",
  )
  use quiet <- glint.flag(quiet_flag())
  use _, _, flags <- glint.command()

  let assert Ok(is_quiet) = quiet(flags)
  types_catalog(log_level_from_quiet(is_quiet))
}

/// Builds the validate subcommand.
@internal
pub fn validate_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help(
    "Validate .caffeine blueprints and expectations without writing output",
  )
  use quiet <- glint.flag(quiet_flag())
  use target <- glint.flag(target_flag())
  use blueprint_file <- glint.named_arg("blueprint_file")
  use expectations_dir <- glint.named_arg("expectations_dir")
  use named, _, flags <- glint.command()

  let assert Ok(is_quiet) = quiet(flags)
  let assert Ok(target) = target(flags)
  let log_level = log_level_from_quiet(is_quiet)
  let bp = blueprint_file(named)
  let exp_dir = expectations_dir(named)

  validate(bp, exp_dir, target, log_level)
}

/// Builds the lsp subcommand.
@internal
pub fn lsp_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help("Start the Language Server Protocol server")
  use _, _, _ <- glint.command()

  Error(
    "LSP mode requires the compiled binary (main.mjs intercepts this argument)",
  )
}

/// Builds the root command for version display.
@internal
pub fn root_command() -> glint.Command(Result(Nil, String)) {
  use <- glint.command_help(
    "A compiler for generating reliability artifacts from service expectation definitions.\n\nVersion: "
    <> constants.version,
  )
  use _, _, _ <- glint.command()

  Ok(Nil)
}

// --- Business logic ---

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
  target: String,
  log_level: LogLevel,
) -> Result(Nil, String) {
  use output <- result.try(load_and_compile(
    blueprint_file,
    expectations_dir,
    target,
    log_level,
  ))

  case output_path {
    option.None -> {
      compile_presenter.log(log_level, output.terraform)
      case output.dependency_graph {
        option.Some(graph) -> {
          compile_presenter.log(log_level, "")
          compile_presenter.log(log_level, "--- Dependency Graph (Mermaid) ---")
          compile_presenter.log(log_level, graph)
        }
        option.None -> Nil
      }
      Ok(Nil)
    }
    option.Some(path) -> {
      let #(output_file, output_dir) = case simplifile.is_directory(path) {
        Ok(True) -> #(filepath.join(path, "main.tf"), path)
        _ -> #(path, filepath.directory_name(path))
      }
      use _ <- result.try(
        simplifile.write(output_file, output.terraform)
        |> result.map_error(fn(err) {
          "Error writing output file: " <> string.inspect(err)
        }),
      )
      compile_presenter.log(
        log_level,
        "Successfully compiled " <> target <> " to " <> output_file,
      )

      // Write dependency graph if present
      case output.dependency_graph {
        option.Some(graph) -> {
          let graph_file = filepath.join(output_dir, "dependency_graph.mmd")
          case simplifile.write(graph_file, graph) {
            Ok(_) ->
              compile_presenter.log(
                log_level,
                "Dependency graph written to " <> graph_file,
              )
            Error(err) ->
              compile_presenter.log(
                log_level,
                "Warning: could not write dependency graph: "
                  <> string.inspect(err),
              )
          }
        }
        option.None -> Nil
      }
      Ok(Nil)
    }
  }
}

fn validate(
  blueprint_file: String,
  expectations_dir: String,
  target: String,
  log_level: LogLevel,
) -> Result(Nil, String) {
  use _output <- result.try(load_and_compile(
    blueprint_file,
    expectations_dir,
    target,
    log_level,
  ))

  compile_presenter.log(log_level, "Validation passed")
  Ok(Nil)
}

/// Discovers, reads, and compiles blueprint and expectation files.
fn load_and_compile(
  blueprint_file: String,
  expectations_dir: String,
  target: String,
  log_level: LogLevel,
) -> Result(CompilationOutput, String) {
  // Discover expectation files
  use expectation_paths <- result.try(
    file_discovery.get_caffeine_files(expectations_dir)
    |> result.map_error(fn(err) { format_compilation_error(err) }),
  )

  // Read blueprint source
  use blueprint_content <- result.try(read_file(blueprint_file))
  let blueprint = SourceFile(path: blueprint_file, content: blueprint_content)

  // Read all expectation sources
  use expectations <- result.try(
    expectation_paths
    |> list.map(fn(path) {
      simplifile.read(path)
      |> result.map(fn(content) { SourceFile(path: path, content: content) })
      |> result.map_error(fn(err) {
        "Error reading file: "
        <> simplifile.describe_error(err)
        <> " ("
        <> path
        <> ")"
      })
    })
    |> result.all(),
  )

  // Compile with presentation output
  compile_presenter.compile_with_output(
    blueprint,
    expectations,
    target,
    log_level,
  )
  |> result.map_error(fn(err) { format_compilation_error(err) })
}

fn format_command(
  path: String,
  check_only: Bool,
  log_level: LogLevel,
) -> Result(Nil, String) {
  use file_paths <- result.try(
    file_discovery.discover(path)
    |> result.map_error(fn(err) { "Format error: " <> err }),
  )

  use has_unformatted <- result.try(
    list.try_fold(file_paths, False, fn(acc, file_path) {
      use changed <- result.try(format_single_file(
        file_path,
        check_only,
        log_level,
      ))
      Ok(acc || changed)
    }),
  )

  case check_only && has_unformatted {
    True -> Error("Some files are not formatted")
    False -> Ok(Nil)
  }
}

fn format_single_file(
  file_path: String,
  check_only: Bool,
  log_level: LogLevel,
) -> Result(Bool, String) {
  use content <- result.try(read_file(file_path))
  use formatted <- result.try(
    formatter.format(content)
    |> result.map_error(fn(err) {
      "Error formatting " <> file_path <> ": " <> err
    }),
  )

  case formatted == content {
    True -> Ok(False)
    False if check_only -> {
      compile_presenter.log(log_level, file_path)
      Ok(True)
    }
    False -> {
      use _ <- result.try(write_file(file_path, formatted))
      compile_presenter.log(log_level, "Formatted " <> file_path)
      Ok(False)
    }
  }
}

fn read_file(path: String) -> Result(String, String) {
  simplifile.read(path)
  |> result.map_error(fn(err) {
    "Error reading file: "
    <> simplifile.describe_error(err)
    <> " ("
    <> path
    <> ")"
  })
}

fn write_file(path: String, content: String) -> Result(Nil, String) {
  simplifile.write(path, content)
  |> result.map_error(fn(err) {
    "Error writing file: "
    <> simplifile.describe_error(err)
    <> " ("
    <> path
    <> ")"
  })
}

fn artifacts_catalog(log_level: LogLevel) -> Result(Nil, String) {
  compile_presenter.log(log_level, "Artifact Catalog")
  compile_presenter.log(log_level, string.repeat("=", 16))
  compile_presenter.log(log_level, "")

  stdlib_artifacts.standard_library()
  |> list.map(display.pretty_print_artifact)
  |> string.join("\n\n")
  |> compile_presenter.log(log_level, _)

  compile_presenter.log(log_level, "")
  Ok(Nil)
}

fn types_catalog(log_level: LogLevel) -> Result(Nil, String) {
  compile_presenter.log(log_level, "Type System Reference")
  compile_presenter.log(log_level, string.repeat("=", 21))
  compile_presenter.log(log_level, "")

  [
    display.pretty_print_category(
      "PrimitiveTypes",
      "Base value types for simple data",
      types.primitive_all_type_metas(),
    ),
    display.pretty_print_category(
      "CollectionTypes",
      "Container types for grouping values",
      types.collection_all_type_metas(),
    ),
    display.pretty_print_category(
      "StructuredTypes",
      "Named fields with typed values",
      types.structured_all_type_metas(),
    ),
    display.pretty_print_category(
      "ModifierTypes",
      "Wrappers that change how values are handled",
      types.modifier_all_type_metas(),
    ),
    display.pretty_print_category(
      "RefinementTypes",
      "Constraints that restrict allowed values",
      types.refinement_all_type_metas(),
    ),
  ]
  |> string.join("\n\n")
  |> compile_presenter.log(log_level, _)

  compile_presenter.log(log_level, "")
  Ok(Nil)
}

/// Formats a CompilationError using the rich error presenter with color support.
fn format_compilation_error(err: errors.CompilationError) -> String {
  let color_mode = color.detect_color_mode()
  let rich_errors = rich_error.from_compilation_errors(err)
  error_presenter.render_all(rich_errors, color_mode)
}
