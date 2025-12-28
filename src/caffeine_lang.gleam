import argv
import caffeine_lang/cli/exit_status_codes.{
  type ExitStatusCodes, exit_status_code_to_int,
}
import caffeine_lang/cli/handler

// Needed for both erlang and js targets.
@external(erlang, "erlang", "halt")
@external(javascript, "./caffeine_lang_ffi.mjs", "halt")
fn halt(code: Int) -> Nil

/// Entry point for the Caffeine language CLI application.
pub fn main() {
  let exit_status = handler.handle_args(argv.load().arguments)
  case exit_status {
    exit_status_codes.Success -> Nil
    _ -> halt(exit_status_code_to_int(exit_status))
  }
}

/// Entry point for Erlang escript compatibility.
pub fn run(args: List(String)) -> ExitStatusCodes {
  handler.handle_args(args)
}
