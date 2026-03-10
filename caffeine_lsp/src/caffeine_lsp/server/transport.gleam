/// Stdio transport for the LSP base protocol.
/// Handles Content-Length framing over stdin/stdout.
import gleam/bit_array
import gleam/int
import gleam/option.{type Option}
import gleam/result
import gleam/string

// --- FFI bindings ---

/// Set stdin/stdout to binary mode.
@external(erlang, "caffeine_lsp_ffi", "init_io")
pub fn init_io() -> Nil

/// Read a single line from stdin (up to newline).
@external(erlang, "caffeine_lsp_ffi", "read_line")
fn read_line() -> Result(String, Nil)

/// Read exactly n bytes from stdin.
@external(erlang, "caffeine_lsp_ffi", "read_bytes")
fn read_bytes(n: Int) -> Result(String, Nil)

/// Write raw bytes to stdout.
@external(erlang, "caffeine_lsp_ffi", "write_stdout")
fn write_stdout(data: String) -> Nil

/// Write a message to stderr for logging.
@external(erlang, "caffeine_lsp_ffi", "write_stderr")
pub fn log(msg: String) -> Nil

/// Safely call a function, catching crashes.
@external(erlang, "caffeine_lsp_ffi", "rescue")
pub fn rescue(f: fn() -> a) -> Result(a, Nil)

// --- Reading ---

/// Read a single LSP message from stdin.
/// Parses Content-Length headers, then reads the JSON body.
pub fn read_message() -> Result(String, Nil) {
  use content_length <- result.try(read_headers(option.None))
  read_bytes(content_length)
}

/// Parse headers recursively until an empty line is found.
fn read_headers(content_length: Option(Int)) -> Result(Int, Nil) {
  use line <- result.try(read_line())
  let trimmed = string.trim(line)
  case trimmed {
    "" -> {
      case content_length {
        option.Some(n) -> Ok(n)
        option.None -> Error(Nil)
      }
    }
    _ -> {
      let new_cl = case string.starts_with(trimmed, "Content-Length: ") {
        True -> {
          let n_str =
            string.replace(in: trimmed, each: "Content-Length: ", with: "")
          case int.parse(n_str) {
            Ok(n) -> option.Some(n)
            Error(_) -> content_length
          }
        }
        False -> content_length
      }
      read_headers(new_cl)
    }
  }
}

// --- Writing ---

/// Write a raw JSON-RPC message to stdout with Content-Length header.
pub fn send_raw(body: String) -> Nil {
  let body_bytes = <<body:utf8>>
  let length = bit_array.byte_size(body_bytes)
  let header = "Content-Length: " <> int.to_string(length) <> "\r\n\r\n"
  write_stdout(header <> body)
}
