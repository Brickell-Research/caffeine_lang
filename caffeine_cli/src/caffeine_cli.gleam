import argv
import caffeine_cli/handler
import gleam/bool
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/result
import gleam/string

/// Parsed CLI arguments.
pub type ParsedArgs {
  ParsedArgs(
    command: String,
    flags: Dict(String, String),
    positional: List(String),
  )
}

/// Parse a list of string arguments into a command, flags, and positional args.
@internal
pub fn parse_args(args: List(String)) -> ParsedArgs {
  parse_loop(args, "", dict.new(), [])
}

/// Entry point for the Caffeine language CLI application.
pub fn main() {
  let args = argv.load().arguments
  case run(args) {
    Ok(Nil) -> Nil
    Error(msg) -> {
      io.println(msg)
      halt(1)
    }
  }
}

/// Entry point for Erlang escript compatibility and testing.
pub fn run(args: List(String)) -> Result(Nil, String) {
  run_with_output(args, io.println)
}

/// Run with a custom output function. Useful for testing to suppress stdout.
@internal
pub fn run_with_output(
  args: List(String),
  output: fn(String) -> Nil,
) -> Result(Nil, String) {
  let parsed = parse_args(args)

  use <- bool.lazy_guard(
    has_flag(parsed.flags, "version") || has_flag(parsed.flags, "v"),
    fn() {
      output(handler.version_string())
      Ok(Nil)
    },
  )

  use <- bool.lazy_guard(
    has_flag(parsed.flags, "help")
      || has_flag(parsed.flags, "h")
      || parsed.command == "",
    fn() {
      output(handler.help_text())
      Ok(Nil)
    },
  )

  dispatch(parsed)
}

// --- Private functions ---

@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_cli_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

fn parse_loop(
  args: List(String),
  command: String,
  flags: Dict(String, String),
  positional: List(String),
) -> ParsedArgs {
  case args {
    [] ->
      ParsedArgs(
        command: command,
        flags: flags,
        positional: list.reverse(positional),
      )
    [arg, ..rest] ->
      case string.starts_with(arg, "--") {
        True -> {
          let flag = string.drop_start(arg, 2)
          case string.split_once(flag, "=") {
            Ok(#(key, value)) ->
              parse_loop(
                rest,
                command,
                dict.insert(flags, key, value),
                positional,
              )
            Error(_) ->
              parse_loop(
                rest,
                command,
                dict.insert(flags, flag, "true"),
                positional,
              )
          }
        }
        False ->
          case string.starts_with(arg, "-") {
            True -> {
              let flag = string.drop_start(arg, 1)
              parse_loop(
                rest,
                command,
                dict.insert(flags, flag, "true"),
                positional,
              )
            }
            False ->
              case command {
                "" -> parse_loop(rest, arg, flags, positional)
                _ -> parse_loop(rest, command, flags, [arg, ..positional])
              }
          }
      }
  }
}

fn get_bool_flag(flags: Dict(String, String), key: String) -> Bool {
  case dict.get(flags, key) {
    Ok("true") -> True
    _ -> False
  }
}

fn get_string_flag(
  flags: Dict(String, String),
  key: String,
  default: String,
) -> String {
  dict.get(flags, key) |> result.unwrap(default)
}

fn has_flag(flags: Dict(String, String), key: String) -> Bool {
  dict.has_key(flags, key)
}

/// Dispatch parsed arguments to the appropriate command handler.
fn dispatch(parsed: ParsedArgs) -> Result(Nil, String) {
  let quiet = get_bool_flag(parsed.flags, "quiet")
  let target = get_string_flag(parsed.flags, "target", "terraform")

  case parsed.command {
    "compile" -> handler.run_compile(quiet, target, parsed.positional)
    "validate" -> handler.run_validate(quiet, target, parsed.positional)
    "format" -> {
      let check = get_bool_flag(parsed.flags, "check")
      handler.run_format(quiet, check, parsed.positional)
    }
    "artifacts" -> handler.run_artifacts(quiet)
    "types" -> handler.run_types(quiet)
    "lsp" -> handler.run_lsp()
    _ -> Error("Unknown command: " <> parsed.command)
  }
}
