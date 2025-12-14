import gleam/int
import gleam/list
import gleam/string

/// Sanitize string to valid Terraform resource name.
///
/// Per Terraform docs (https://developer.hashicorp.com/terraform/language/syntax/configuration):
/// - Identifiers can contain letters, digits, underscores (_), and hyphens (-)
/// - The first character must not be a digit
///
/// This function:
/// - Replaces illegal characters with underscores
/// - Prefixes with underscore if name starts with a digit
pub fn sanitize_terraform_identifier(name: String) -> String {
  let sanitized =
    name
    |> string.to_graphemes
    |> list.map(fn(char) {
      case is_valid_identifier_char(char) {
        True -> char
        False -> "_"
      }
    })
    |> string.concat

  // Prefix with underscore if starts with a digit
  case string.first(sanitized) {
    Ok(c) ->
      case is_digit(c) {
        True -> "_" <> sanitized
        False -> sanitized
      }
    _ -> sanitized
  }
}

fn is_valid_identifier_char(char: String) -> Bool {
  is_letter(char) || is_digit(char) || char == "_" || char == "-"
}

fn is_letter(char: String) -> Bool {
  case char |> string.lowercase {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

fn is_digit(char: String) -> Bool {
  case char |> int.parse {
    Ok(_) -> True
    Error(_) -> False
  }
}
