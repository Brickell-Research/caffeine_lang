pub type ExitStatusCodes {
  Success
  Failure
}

pub fn exist_status_code_to_int(status: ExitStatusCodes) -> Int {
  case status {
    Success -> 0
    Failure -> 1
  }
}
