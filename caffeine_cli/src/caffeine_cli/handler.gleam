import caffeine_cli/compile_presenter.{type LogLevel}
import caffeine_cli/display
import caffeine_cli/exit_status_codes.{type ExitStatusCodes}
import caffeine_cli/file_discovery
import caffeine_cli/format_file_discovery
import caffeine_lang/constants
import caffeine_lang/frontend/formatter
import caffeine_lang/source_file.{SourceFile}
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import caffeine_lsp
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

/// Handles CLI arguments and dispatches to appropriate commands.
@internal
pub fn handle_args(args: List(String)) -> ExitStatusCodes {
  case args {
    ["compile", "--quiet", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        compile_presenter.Minimal,
      )
    ["compile", "--quiet", blueprint_file, expectations_dir] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.None,
        compile_presenter.Minimal,
      )
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        compile_presenter.Verbose,
      )
    ["compile", blueprint_file, expectations_dir] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.None,
        compile_presenter.Verbose,
      )
    ["--help"] | ["-h"] -> {
      print_usage(compile_presenter.Verbose)
      exit_status_codes.Success
    }
    ["--version"] | ["-V"] -> {
      print_version(compile_presenter.Verbose)
      exit_status_codes.Success
    }
    ["artifacts"] -> artifacts_catalog(compile_presenter.Verbose)
    ["artifacts", "--quiet"] | ["--quiet", "artifacts"] ->
      artifacts_catalog(compile_presenter.Minimal)
    ["types"] -> types_catalog(compile_presenter.Verbose)
    ["types", "--quiet"] | ["--quiet", "types"] ->
      types_catalog(compile_presenter.Minimal)
    ["--quiet", "--help"]
    | ["--quiet", "-h"]
    | ["--help", "--quiet"]
    | ["-h", "--quiet"] -> {
      print_usage(compile_presenter.Minimal)
      exit_status_codes.Success
    }
    ["--quiet", "--version"]
    | ["--quiet", "-V"]
    | ["--version", "--quiet"]
    | ["-V", "--quiet"] -> {
      print_version(compile_presenter.Minimal)
      exit_status_codes.Success
    }
    ["format", "--check", "--quiet", path]
    | ["format", "--quiet", "--check", path] ->
      format_command(path, True, compile_presenter.Minimal)
    ["format", "--check", path] ->
      format_command(path, True, compile_presenter.Verbose)
    ["format", "--quiet", path] ->
      format_command(path, False, compile_presenter.Minimal)
    ["format", path] -> format_command(path, False, compile_presenter.Verbose)
    ["lsp"] -> {
      caffeine_lsp.start()
      exit_status_codes.Success
    }
    ["--quiet"] -> {
      print_usage(compile_presenter.Minimal)
      exit_status_codes.Success
    }
    [] -> {
      print_usage(compile_presenter.Verbose)
      exit_status_codes.Success
    }
    _ -> {
      compile_presenter.log(
        compile_presenter.Verbose,
        "Error: Invalid arguments",
      )
      compile_presenter.log(compile_presenter.Verbose, "")
      print_usage(compile_presenter.Verbose)
      exit_status_codes.Failure
    }
  }
}

fn compile(
  blueprint_file: String,
  expectations_dir: String,
  output_path: Option(String),
  log_level: LogLevel,
) -> ExitStatusCodes {
  {
    // Discover expectation files
    use expectation_paths <- result.try(
      file_discovery.get_caffeine_files(expectations_dir)
      |> result.map_error(fn(err) { "File discovery error: " <> err.msg }),
    )

    // Read blueprint source
    use blueprint_content <- result.try(
      simplifile.read(blueprint_file)
      |> result.map_error(fn(err) {
        "Error reading blueprint file: "
        <> simplifile.describe_error(err)
        <> " ("
        <> blueprint_file
        <> ")"
      }),
    )
    let blueprint = SourceFile(path: blueprint_file, content: blueprint_content)

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
    use output <- result.try(
      compile_presenter.compile_with_output(blueprint, expectations, log_level)
      |> result.map_error(fn(err) { "Compilation error: " <> err.msg }),
    )

    case output_path {
      option.None -> {
        compile_presenter.log(log_level, output.terraform)
        case output.dependency_graph {
          option.Some(graph) -> {
            compile_presenter.log(log_level, "")
            compile_presenter.log(
              log_level,
              "--- Dependency Graph (Mermaid) ---",
            )
            compile_presenter.log(log_level, graph)
          }
          option.None -> Nil
        }
        Ok(Nil)
      }
      option.Some(path) -> {
        let #(output_file, output_dir) = case simplifile.is_directory(path) {
          Ok(True) -> #(path <> "/main.tf", path)
          _ -> #(path, directory_of(path))
        }
        use _ <- result.try(
          simplifile.write(output_file, output.terraform)
          |> result.map_error(fn(err) {
            "Error writing output file: " <> string.inspect(err)
          }),
        )
        compile_presenter.log(
          log_level,
          "Successfully compiled to " <> output_file,
        )

        // Write dependency graph if present
        case output.dependency_graph {
          option.Some(graph) -> {
            let graph_file = output_dir <> "/dependency_graph.mmd"
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
  |> result_to_exit_status(log_level)
}

fn format_command(
  path: String,
  check_only: Bool,
  log_level: LogLevel,
) -> ExitStatusCodes {
  {
    use file_paths <- result.try(
      format_file_discovery.discover(path)
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
  |> result_to_exit_status(log_level)
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

fn print_usage(log_level: LogLevel) {
  compile_presenter.log(log_level, "caffeine " <> constants.version)
  compile_presenter.log(
    log_level,
    "A compiler for generating reliability artifacts from service expectation definitions.",
  )
  compile_presenter.log(log_level, "")
  compile_presenter.log(log_level, "USAGE:")
  compile_presenter.log(
    log_level,
    "    caffeine compile [--quiet] <blueprint.caffeine> <expectations_directory> [output_file]",
  )
  compile_presenter.log(log_level, "    caffeine artifacts [--quiet]")
  compile_presenter.log(log_level, "    caffeine types [--quiet]")
  compile_presenter.log(
    log_level,
    "    caffeine format [--quiet] [--check] <path>",
  )
  compile_presenter.log(log_level, "    caffeine lsp")
  compile_presenter.log(log_level, "")
  compile_presenter.log(log_level, "COMMANDS:")
  compile_presenter.log(
    log_level,
    "    compile          Compile .caffeine blueprints and expectations to output",
  )
  compile_presenter.log(
    log_level,
    "    artifacts        List available artifacts from the standard library",
  )
  compile_presenter.log(
    log_level,
    "    types            Show the type system reference with all supported types",
  )
  compile_presenter.log(
    log_level,
    "    format           Format .caffeine files",
  )
  compile_presenter.log(
    log_level,
    "    lsp              Start the Language Server Protocol server",
  )
  compile_presenter.log(log_level, "")
  compile_presenter.log(log_level, "ARGUMENTS:")
  compile_presenter.log(
    log_level,
    "    <blueprint.caffeine>       Path to the blueprints .caffeine file",
  )
  compile_presenter.log(
    log_level,
    "    <expectations_directory>   Directory containing expectations .caffeine files",
  )
  compile_presenter.log(
    log_level,
    "    [output_file]              Output file path or directory (prints to stdout if omitted)",
  )
  compile_presenter.log(log_level, "")
  compile_presenter.log(log_level, "OPTIONS:")
  compile_presenter.log(
    log_level,
    "    --quiet          Suppress compilation progress output",
  )
  compile_presenter.log(
    log_level,
    "    -h, --help       Print help information",
  )
  compile_presenter.log(
    log_level,
    "    -V, --version    Print version information",
  )
}

fn print_version(log_level: LogLevel) {
  compile_presenter.log(log_level, "caffeine " <> constants.version)
}

fn artifacts_catalog(log_level: LogLevel) -> ExitStatusCodes {
  compile_presenter.log(log_level, "Artifact Catalog")
  compile_presenter.log(log_level, string.repeat("=", 16))
  compile_presenter.log(log_level, "")

  stdlib_artifacts.standard_library()
  |> list.map(display.pretty_print_artifact)
  |> string.join("\n\n")
  |> compile_presenter.log(log_level, _)

  compile_presenter.log(log_level, "")
  exit_status_codes.Success
}

fn types_catalog(log_level: LogLevel) -> ExitStatusCodes {
  compile_presenter.log(log_level, "Type System Reference")
  compile_presenter.log(log_level, string.repeat("=", 21))
  compile_presenter.log(log_level, "")

  display.pretty_print_category(
    "Types",
    "All supported types in the Caffeine type system",
    types.all_type_metas(),
  )
  |> compile_presenter.log(log_level, _)

  compile_presenter.log(log_level, "")
  exit_status_codes.Success
}

/// Extracts the directory portion of a file path.
fn directory_of(path: String) -> String {
  case string.split(path, "/") |> list.reverse {
    [_, ..rest] ->
      case list.reverse(rest) {
        [] -> "."
        [""] -> "/"
        parts -> string.join(parts, "/")
      }
    [] -> "."
  }
}

fn result_to_exit_status(
  res: Result(Nil, String),
  log_level: LogLevel,
) -> ExitStatusCodes {
  case res {
    Ok(_) -> exit_status_codes.Success
    Error(msg) -> {
      compile_presenter.log(log_level, msg)
      exit_status_codes.Failure
    }
  }
}
