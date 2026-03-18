import argv
import caffeine_cli/handler
import gleam/dict.{type Dict}
import gleam/io
import gleam/list
import gleam/string

// Needed for both erlang and js targets.
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_cli_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

// --- Arg parsing ---

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
          let flag = string.slice(arg, 2, string.length(arg))
          case string.split(flag, "=") {
            [key, ..value_parts] if value_parts != [] ->
              parse_loop(
                rest,
                command,
                dict.insert(flags, key, string.join(value_parts, "=")),
                positional,
              )
            _ ->
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
              let flag = string.slice(arg, 1, string.length(arg))
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
                _ ->
                  parse_loop(rest, command, flags, [arg, ..positional])
              }
          }
      }
  }
}

// --- Flag helpers ---

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
  case dict.get(flags, key) {
    Ok(value) -> value
    Error(_) -> default
  }
}

fn has_flag(flags: Dict(String, String), key: String) -> Bool {
  dict.has_key(flags, key)
}

// --- Routing ---

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
  let parsed = parse_args(args)

  // Handle --version / -v anywhere
  case has_flag(parsed.flags, "version") || has_flag(parsed.flags, "v") {
    True -> {
      io.println(handler.version_string())
      Ok(Nil)
    }
    False ->
      // Handle --help or no command
      case
        has_flag(parsed.flags, "help")
        || has_flag(parsed.flags, "h")
        || parsed.command == ""
      {
        True -> {
          io.println(handler.help_text())
          Ok(Nil)
        }
        False -> dispatch(parsed)
      }
  }
}
