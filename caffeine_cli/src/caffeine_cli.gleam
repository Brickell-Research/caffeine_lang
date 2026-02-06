import argv
import caffeine_cli/handler
import gleam/io
import glint

// Needed for both erlang and js targets.
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_cli_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

/// Builds the glint CLI application with all subcommands.
@internal
pub fn build_app() -> glint.Glint(Result(Nil, String)) {
  glint.new()
  |> glint.without_exit()
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.with_name("caffeine")
  |> glint.add(at: [], do: handler.root_command())
  |> glint.add(at: ["compile"], do: handler.compile_command())
  |> glint.add(at: ["validate"], do: handler.validate_command())
  |> glint.add(at: ["format"], do: handler.format_command_builder())
  |> glint.add(at: ["artifacts"], do: handler.artifacts_command())
  |> glint.add(at: ["types"], do: handler.types_command())
  |> glint.add(at: ["lsp"], do: handler.lsp_command())
}

/// Entry point for the Caffeine language CLI application.
pub fn main() {
  let args = argv.load().arguments
  case args {
    ["--version"] | ["-v"] -> io.println(handler.version_string())
    [] ->
      build_app()
      |> glint.run_and_handle(["--help"], fn(_) { Nil })
    _ ->
      build_app()
      |> glint.run_and_handle(args, fn(result) {
        case result {
          Ok(Nil) -> Nil
          Error(msg) -> {
            io.println(msg)
            halt(1)
          }
        }
      })
  }
}

/// Entry point for Erlang escript compatibility and testing.
pub fn run(args: List(String)) -> Result(Nil, String) {
  case args {
    ["--version"] | ["-v"] -> {
      io.println(handler.version_string())
      Ok(Nil)
    }
    _ ->
      case glint.execute(build_app(), args) {
        Ok(glint.Out(result)) -> result
        Ok(glint.Help(_)) -> Ok(Nil)
        Error(err) -> Error(err)
      }
  }
}
