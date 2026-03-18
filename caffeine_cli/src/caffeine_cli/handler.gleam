import caffeine_cli/color
import caffeine_cli/compile_presenter.{type LogLevel}
import caffeine_cli/display
import caffeine_cli/error_presenter
import caffeine_cli/file_discovery
import caffeine_lang/compiler.{type CompilationOutput}
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/frontend/formatter
import caffeine_lang/source_file.{SourceFile, VendorMeasurementSource}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import filepath
import gleam/bool
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

// --- Version ---

/// Returns the version string for `--version` output.
pub fn version_string() -> String {
  "caffeine " <> constants.version <> " (Brickell Research)"
}

// --- Help text ---

/// Returns the top-level help text.
pub fn help_text() -> String {
  string.join(
    [
      "caffeine - A compiler for generating reliability artifacts from service expectation definitions.",
      "",
      "Version: " <> constants.version,
      "",
      "USAGE:",
      "  caffeine <command> [flags] [arguments]",
      "",
      "COMMANDS:",
      "  compile <measurements_dir> <expectations_dir> [output_path]",
      "    Compile .caffeine measurements and expectations to output",
      "",
      "  validate <measurements_dir> <expectations_dir>",
      "    Validate .caffeine measurements and expectations without writing output",
      "",
      "  format <path>",
      "    Format .caffeine files",
      "",
      "  artifacts",
      "    List available artifacts from the standard library",
      "",
      "  types",
      "    Show the type system reference with all supported types",
      "",
      "  lsp",
      "    Start the Language Server Protocol server",
      "",
      "FLAGS:",
      "  --quiet       Suppress compilation progress output",
      "  --check       Check formatting without modifying files (format only)",
      "  --target      Code generation target: terraform or opentofu (default: terraform)",
      "  -v, --version Show version information",
      "  --help        Show this help message",
    ],
    "\n",
  )
}

// --- Command functions ---

/// Run the compile command.
@internal
pub fn run_compile(
  quiet: Bool,
  target: String,
  positional: List(String),
) -> Result(Nil, String) {
  use #(measurements_dir, expectations_dir, output_path) <- result.try(
    case positional {
      [m, e, o, ..] -> Ok(#(m, e, option.Some(o)))
      [m, e] -> Ok(#(m, e, option.None))
      _ ->
        Error(
          "Usage: caffeine compile <measurements_dir> <expectations_dir> [output_path]",
        )
    },
  )

  use target <- result.try(validate_target(target))
  let log_level = log_level_from_quiet(quiet)
  compile(measurements_dir, expectations_dir, output_path, target, log_level)
}

/// Run the validate command.
@internal
pub fn run_validate(
  quiet: Bool,
  target: String,
  positional: List(String),
) -> Result(Nil, String) {
  use #(measurements_dir, expectations_dir) <- result.try(case positional {
    [m, e, ..] -> Ok(#(m, e))
    _ -> Error("Usage: caffeine validate <measurements_dir> <expectations_dir>")
  })

  use target <- result.try(validate_target(target))
  let log_level = log_level_from_quiet(quiet)
  validate(measurements_dir, expectations_dir, target, log_level)
}

/// Run the format command.
@internal
pub fn run_format(
  quiet: Bool,
  check_only: Bool,
  positional: List(String),
) -> Result(Nil, String) {
  use path <- result.try(case positional {
    [p, ..] -> Ok(p)
    _ -> Error("Usage: caffeine format <path>")
  })

  let log_level = log_level_from_quiet(quiet)
  format_command(path, check_only, log_level)
}

/// Run the artifacts command.
@internal
pub fn run_artifacts(quiet: Bool) -> Result(Nil, String) {
  artifacts_catalog(log_level_from_quiet(quiet))
}

/// Run the types command.
@internal
pub fn run_types(quiet: Bool) -> Result(Nil, String) {
  types_catalog(log_level_from_quiet(quiet))
}

/// Run the lsp command.
@internal
pub fn run_lsp() -> Result(Nil, String) {
  Error(
    "LSP mode requires the compiled binary (main.mjs intercepts this argument)",
  )
}

// --- Private functions ---

fn log_level_from_quiet(quiet: Bool) -> LogLevel {
  use <- bool.guard(quiet, compile_presenter.Minimal)
  compile_presenter.Verbose
}

fn validate_target(target: String) -> Result(String, String) {
  case target {
    "terraform" | "opentofu" -> Ok(target)
    _ ->
      Error(
        "Invalid target: " <> target <> ". Must be one of: terraform, opentofu",
      )
  }
}

fn compile(
  measurements_dir: String,
  expectations_dir: String,
  output_path: Option(String),
  target: String,
  log_level: LogLevel,
) -> Result(Nil, String) {
  use output <- result.try(load_and_compile(
    measurements_dir,
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
  measurements_dir: String,
  expectations_dir: String,
  target: String,
  log_level: LogLevel,
) -> Result(Nil, String) {
  use _output <- result.try(load_and_compile(
    measurements_dir,
    expectations_dir,
    target,
    log_level,
  ))

  compile_presenter.log(log_level, "Validation passed")
  Ok(Nil)
}

/// Discovers, reads, and compiles measurement and expectation files.
fn load_and_compile(
  measurements_dir: String,
  expectations_dir: String,
  target: String,
  log_level: LogLevel,
) -> Result(CompilationOutput, String) {
  // Discover expectation files
  use expectation_paths <- result.try(
    file_discovery.get_caffeine_files(expectations_dir)
    |> result.map_error(fn(err) { format_compilation_error(err) }),
  )

  // Discover and read measurement sources
  use measurement_entries <- result.try(
    file_discovery.get_measurement_files(measurements_dir)
    |> result.map_error(fn(err) { format_compilation_error(err) }),
  )
  use measurements <- result.try(
    measurement_entries
    |> list.map(fn(entry) {
      let #(path, v) = entry
      simplifile.read(path)
      |> result.map(fn(content) {
        VendorMeasurementSource(
          source: SourceFile(path: path, content: content),
          vendor: v,
        )
      })
      |> result.map_error(fn(err) {
        "Error reading measurement file: "
        <> simplifile.describe_error(err)
        <> " ("
        <> path
        <> ")"
      })
    })
    |> result.all(),
  )

  // Read all expectation sources
  use expectations <- result.try(
    expectation_paths
    |> list.map(fn(path) {
      simplifile.read(path)
      |> result.map(fn(content) { SourceFile(path: path, content: content) })
      |> result.map_error(fn(err) {
        "Error reading expectation file: "
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
    measurements,
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

  stdlib_artifacts.slo_params()
  |> display.pretty_print_slo_params
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

fn format_compilation_error(err: errors.CompilationError) -> String {
  let color_mode = color.detect_color_mode()
  let errs = errors.to_list(err)
  error_presenter.render_all(errs, color_mode)
}
