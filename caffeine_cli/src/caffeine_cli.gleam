import argv
import caffeine_cli/exit_status_codes.{
  type ExitStatusCodes, exit_status_code_to_int,
}
import caffeine_cli/handler
import glint

// Needed for both erlang and js targets.
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_cli_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

/// Builds the glint CLI application with all subcommands.
@internal
pub fn build_app() -> glint.Glint(ExitStatusCodes) {
  glint.new()
  |> glint.without_exit()
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.with_name("caffeine")
  |> glint.add(at: [], do: handler.root_command())
  |> glint.add(at: ["compile"], do: handler.compile_command())
  |> glint.add(at: ["format"], do: handler.format_command_builder())
  |> glint.add(at: ["artifacts"], do: handler.artifacts_command())
  |> glint.add(at: ["types"], do: handler.types_command())
  |> glint.add(at: ["lsp"], do: handler.lsp_command())
}

/// Entry point for the Caffeine language CLI application.
pub fn main() {
  build_app()
  |> glint.run_and_handle(argv.load().arguments, fn(status) {
    case status {
      exit_status_codes.Success -> Nil
      _ -> halt(exit_status_code_to_int(status))
    }
  })
}

/// Entry point for Erlang escript compatibility and testing.
pub fn run(args: List(String)) -> ExitStatusCodes {
  case glint.execute(build_app(), args) {
    Ok(glint.Out(status)) -> status
    Ok(glint.Help(_)) -> exit_status_codes.Success
    Error(_) -> exit_status_codes.Failure
  }
}
