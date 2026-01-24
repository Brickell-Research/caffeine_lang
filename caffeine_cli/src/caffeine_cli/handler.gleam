import caffeine_cli/exit_status_codes.{type ExitStatusCodes}
import caffeine_cli/file_discovery
import caffeine_lang/common/constants
import caffeine_lang/common/source_file.{SourceFile}
import caffeine_lang/core/compilation_configuration
import caffeine_lang/core/compiler
import caffeine_lang/core/logger.{type LogLevel}
import caffeine_lang/parser/artifacts
import caffeine_lsp
import gleam/io
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
        logger.Minimal,
      )
    ["compile", "--quiet", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, logger.Minimal)
    ["compile", blueprint_file, expectations_dir, output_file] ->
      compile(
        blueprint_file,
        expectations_dir,
        option.Some(output_file),
        logger.Verbose,
      )
    ["compile", blueprint_file, expectations_dir] ->
      compile(blueprint_file, expectations_dir, option.None, logger.Verbose)
    ["--help"] | ["-h"] -> {
      print_usage(logger.Verbose)
      exit_status_codes.Success
    }
    ["--version"] | ["-V"] -> {
      print_version(logger.Verbose)
      exit_status_codes.Success
    }
    ["artifacts"] -> artifacts_catalog(logger.Verbose)
    ["artifacts", "--quiet"] | ["--quiet", "artifacts"] ->
      artifacts_catalog(logger.Minimal)
    ["--quiet", "--help"]
    | ["--quiet", "-h"]
    | ["--help", "--quiet"]
    | ["-h", "--quiet"] -> {
      print_usage(logger.Minimal)
      exit_status_codes.Success
    }
    ["--quiet", "--version"]
    | ["--quiet", "-V"]
    | ["--version", "--quiet"]
    | ["-V", "--quiet"] -> {
      print_version(logger.Minimal)
      exit_status_codes.Success
    }
    ["lsp"] -> {
      caffeine_lsp.start()
      exit_status_codes.Success
    }
    ["--quiet"] -> {
      print_usage(logger.Minimal)
      exit_status_codes.Success
    }
    [] -> {
      print_usage(logger.Verbose)
      exit_status_codes.Success
    }
    _ -> {
      log(logger.Verbose, "Error: Invalid arguments")
      log(logger.Verbose, "")
      print_usage(logger.Verbose)
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
  let config = compilation_configuration.CompilationConfig(log_level: log_level)
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

    // Compile (pure)
    use output <- result.try(
      compiler.compile(blueprint, expectations, config)
      |> result.map_error(fn(err) { "Compilation error: " <> err.msg }),
    )

    case output_path {
      option.None -> {
        log(log_level, output)
        Ok(Nil)
      }
      option.Some(path) -> {
        let output_file = case simplifile.is_directory(path) {
          Ok(True) -> path <> "/main.tf"
          _ -> path
        }
        simplifile.write(output_file, output)
        |> result.map(fn(_) {
          log(log_level, "Successfully compiled to " <> output_file)
        })
        |> result.map_error(fn(err) {
          "Error writing output file: " <> string.inspect(err)
        })
      }
    }
  }
  |> result_to_exit_status(log_level)
}

fn print_usage(log_level: LogLevel) {
  log(log_level, "caffeine " <> constants.version)
  log(
    log_level,
    "A compiler for generating reliability artifacts from service expectation definitions.",
  )
  log(log_level, "")
  log(log_level, "USAGE:")
  log(
    log_level,
    "    caffeine compile [--quiet] <blueprint.caffeine> <expectations_directory> [output_file]",
  )
  log(log_level, "    caffeine artifacts [--quiet]")
  log(log_level, "    caffeine lsp")
  log(log_level, "")
  log(log_level, "COMMANDS:")
  log(
    log_level,
    "    compile          Compile .caffeine blueprints and expectations to output",
  )
  log(
    log_level,
    "    artifacts        List available artifacts from the standard library",
  )
  log(
    log_level,
    "    lsp              Start the Language Server Protocol server",
  )
  log(log_level, "")
  log(log_level, "ARGUMENTS:")
  log(
    log_level,
    "    <blueprint.caffeine>       Path to the blueprints .caffeine file",
  )
  log(
    log_level,
    "    <expectations_directory>   Directory containing expectations .caffeine files",
  )
  log(
    log_level,
    "    [output_file]              Output file path or directory (prints to stdout if omitted)",
  )
  log(log_level, "")
  log(log_level, "OPTIONS:")
  log(log_level, "    --quiet          Suppress compilation progress output")
  log(log_level, "    -h, --help       Print help information")
  log(log_level, "    -V, --version    Print version information")
}

fn print_version(log_level: LogLevel) {
  log(log_level, "caffeine " <> constants.version)
}

fn artifacts_catalog(log_level: LogLevel) -> ExitStatusCodes {
  case artifacts.parse_standard_library() {
    Error(_) -> {
      log(log_level, "Error: Failed to parse standard library artifacts")
      exit_status_codes.Failure
    }
    Ok(artifact_list) -> {
      log(log_level, "Artifact Catalog")
      log(log_level, string.repeat("=", 16))
      log(log_level, "")

      artifact_list
      |> list.map(artifacts.pretty_print_artifact)
      |> string.join("\n\n")
      |> log(log_level, _)

      log(log_level, "")
      exit_status_codes.Success
    }
  }
}

fn log(log_level: LogLevel, message: String) {
  case log_level {
    logger.Verbose -> io.println(message)
    logger.Minimal -> Nil
  }
}

fn result_to_exit_status(
  res: Result(Nil, String),
  log_level: LogLevel,
) -> ExitStatusCodes {
  case res {
    Ok(_) -> exit_status_codes.Success
    Error(msg) -> {
      log(log_level, msg)
      exit_status_codes.Failure
    }
  }
}
