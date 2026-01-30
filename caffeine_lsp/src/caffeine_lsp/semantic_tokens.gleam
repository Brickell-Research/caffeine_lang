import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/string

/// The token type legend — order must match the indices used below.
/// Registered with the client in the server capabilities.
pub const token_types = [
  "keyword", "type", "string", "number", "variable", "comment", "operator",
]

/// Returns the semantic tokens data array for the given source content.
pub fn get_semantic_tokens(content: String) -> List(json.Json) {
  case tokenizer.tokenize(content) {
    Ok(tokens) -> encode_tokens(tokens)
    Error(_) -> []
  }
}

fn encode_tokens(tokens: List(PositionedToken)) -> List(json.Json) {
  encode_loop(tokens, 0, 0, [])
  |> list.reverse
  |> list.map(json.int)
}

fn encode_loop(
  tokens: List(PositionedToken),
  prev_line: Int,
  prev_col: Int,
  acc: List(Int),
) -> List(Int) {
  case tokens {
    [] -> acc
    [tok, ..rest] -> {
      case classify_token(tok.token) {
        Error(_) -> encode_loop(rest, prev_line, prev_col, acc)
        Ok(#(token_type, length)) -> {
          // Tokenizer uses 1-indexed, LSP uses 0-indexed
          let line = tok.line - 1
          let col = tok.column - 1
          let delta_line = line - prev_line
          let delta_col = case delta_line > 0 {
            True -> col
            False -> col - prev_col
          }
          let new_acc =
            list.flatten([
              [0, length, token_type, delta_col, delta_line],
              acc,
            ])
          encode_loop(rest, line, col, new_acc)
        }
      }
    }
  }
}

/// Returns Ok(#(token_type_index, length)) or Error for skip.
fn classify_token(tok: Token) -> Result(#(Int, Int), Nil) {
  case tok {
    // Keywords (index 0)
    token.KeywordBlueprints -> Ok(#(0, 10))
    token.KeywordExpectations -> Ok(#(0, 12))
    token.KeywordFor -> Ok(#(0, 3))
    token.KeywordExtends -> Ok(#(0, 7))
    token.KeywordRequires -> Ok(#(0, 8))
    token.KeywordProvides -> Ok(#(0, 8))
    token.KeywordIn -> Ok(#(0, 2))
    token.KeywordX -> Ok(#(0, 1))
    token.KeywordType -> Ok(#(0, 4))

    // Type keywords (index 1)
    token.KeywordString -> Ok(#(1, 6))
    token.KeywordInteger -> Ok(#(1, 7))
    token.KeywordFloat -> Ok(#(1, 5))
    token.KeywordBoolean -> Ok(#(1, 7))
    token.KeywordList -> Ok(#(1, 4))
    token.KeywordDict -> Ok(#(1, 4))
    token.KeywordOptional -> Ok(#(1, 8))
    token.KeywordDefaulted -> Ok(#(1, 9))
    token.KeywordURL -> Ok(#(1, 3))

    // String literals (index 2) — +2 for quotes
    token.LiteralString(s) -> Ok(#(2, string.length(s) + 2))

    // Number literals (index 3)
    token.LiteralInteger(n) -> Ok(#(3, string.length(int.to_string(n))))
    token.LiteralFloat(f) -> Ok(#(3, string.length(float.to_string(f))))
    token.LiteralTrue -> Ok(#(3, 4))
    token.LiteralFalse -> Ok(#(3, 5))

    // Identifiers (index 4)
    token.Identifier(name) -> Ok(#(4, string.length(name)))

    // Comments (index 5)
    token.CommentLine(text) -> Ok(#(5, string.length(text) + 2))
    token.CommentSection(text) -> Ok(#(5, string.length(text) + 4))

    // Operators (index 6)
    token.SymbolColon -> Ok(#(6, 1))
    token.SymbolPipe -> Ok(#(6, 1))
    token.SymbolDotDot -> Ok(#(6, 2))
    token.SymbolEquals -> Ok(#(6, 1))
    token.SymbolStar -> Ok(#(6, 1))
    token.SymbolPlus -> Ok(#(6, 1))

    // Skip whitespace, braces, parens, brackets, comma, EOF
    _ -> Error(Nil)
  }
}
