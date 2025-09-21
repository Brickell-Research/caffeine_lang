import caffeine_lang/cql/parser
import caffeine_lang/cql/resolver
import gleam/io
import gleam/string

pub fn main() {
  let input = "A * B + C / D - E"
  io.println("Testing mixed operators: " <> input)
  case parser.parse_expr(input) {
    Ok(parsed) -> {
      io.println("Parsed: " <> string.inspect(parsed))
      case resolver.resolve_primitives(parsed) {
        Ok(resolved) -> {
          io.println("Resolved: " <> string.inspect(resolved))
        }
        Error(e) -> {
          io.println("Resolve error: " <> e)
        }
      }
    }
    Error(e) -> {
      io.println("Parse error: " <> e)
    }
  }
}
