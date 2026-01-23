/// Common exit codes for the CLI that aid in proper termination handling from CICD consumers.
pub type ExitStatusCodes {
  Success
  Failure
}

/// Converts an ExitStatusCodes to its common int representation.
@internal
pub fn exit_status_code_to_int(status: ExitStatusCodes) -> Int {
  case status {
    Success -> 0
    Failure -> 1
  }
}
