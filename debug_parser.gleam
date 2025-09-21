import caffeine_lang/cql/parser
import gleam/io

pub fn main() {
  let input = "(A G) + B / (C + (D + E) * F)"
  case parser.parse_expr(input) {
    Ok(parsed) -> {
      io.debug(parsed)
    }
    Error(e) -> {
      io.println("Parse error: " <> e)
    }
  }
}
