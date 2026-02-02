import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer
import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// The token type legend — order must match the indices used below.
/// Registered with the client in the server capabilities.
pub const token_types = [
  "keyword", "type", "string", "number", "variable", "comment", "operator",
  "property", "function", "modifier", "enumMember",
]

/// Returns the semantic tokens data array for the given source content.
pub fn get_semantic_tokens(content: String) -> List(Int) {
  case tokenizer.tokenize(content) {
    Ok(tokens) -> encode_tokens(tokens)
    Error(_) -> []
  }
}

fn encode_tokens(tokens: List(PositionedToken)) -> List(Int) {
  encode_loop(tokens, 0, 0, [])
  |> list.reverse
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
      let next_token = case rest {
        [next, ..] -> Ok(next.token)
        [] -> Error(Nil)
      }
      case classify_token(tok.token, next_token) {
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
          // Prepended in reverse field order since the list is reversed at the end.
          // After reversal, each group becomes: deltaLine, deltaStartChar, length, tokenType, tokenModifiers
          let new_acc =
            list.flatten([
              [0, token_type, length, delta_col, delta_line],
              acc,
            ])
          encode_loop(rest, line, col, new_acc)
        }
      }
    }
  }
}

/// Returns Ok(#(token_type_index, length)) or Error for skip.
fn classify_token(
  tok: Token,
  next: Result(Token, Nil),
) -> Result(#(Int, Int), Nil) {
  case tok {
    // Keywords (index 0)
    token.KeywordBlueprints -> Ok(#(0, 10))
    token.KeywordExpectations -> Ok(#(0, 12))
    token.KeywordFor -> Ok(#(0, 3))
    token.KeywordExtends -> Ok(#(0, 7))
    token.KeywordRequires -> Ok(#(0, 8))
    token.KeywordProvides -> Ok(#(0, 8))
    token.KeywordIn -> Ok(#(0, 2))
    token.KeywordType -> Ok(#(0, 4))

    // Type keywords (index 1)
    token.KeywordString -> Ok(#(1, 6))
    token.KeywordInteger -> Ok(#(1, 7))
    token.KeywordFloat -> Ok(#(1, 5))
    token.KeywordBoolean -> Ok(#(1, 7))
    token.KeywordURL -> Ok(#(1, 3))

    // Modifier keywords (index 9) — collection types and optionality
    token.KeywordList -> Ok(#(9, 4))
    token.KeywordDict -> Ok(#(9, 4))
    token.KeywordOptional -> Ok(#(9, 8))
    token.KeywordDefaulted -> Ok(#(9, 9))

    // Boolean literals as enumMember (index 10)
    token.LiteralTrue -> Ok(#(10, 4))
    token.LiteralFalse -> Ok(#(10, 5))

    // String literals (index 2) — +2 for quotes
    token.LiteralString(s) -> Ok(#(2, string.length(s) + 2))

    // Number literals (index 3)
    token.LiteralInteger(n) -> Ok(#(3, string.length(int.to_string(n))))
    token.LiteralFloat(f) -> Ok(#(3, string.length(float.to_string(f))))

    // Refinement variable (index 4)
    token.KeywordX -> Ok(#(4, 1))

    // Identifiers — context-dependent classification
    token.Identifier(name) -> {
      let len = string.length(name)
      case string.starts_with(name, "_"), next {
        // _extendable followed by ( → function (index 8)
        True, Ok(token.SymbolLeftParen) -> Ok(#(8, len))
        // _extendable not followed by ( → variable (index 4)
        True, _ -> Ok(#(4, len))
        // identifier followed by : → property (index 7)
        False, Ok(token.SymbolColon) -> Ok(#(7, len))
        // plain identifier → variable (index 4)
        _, _ -> Ok(#(4, len))
      }
    }

    // Comments (index 5) — text excludes the leading # or ##
    token.CommentLine(text) -> Ok(#(5, string.length(text) + 1))
    token.CommentSection(text) -> Ok(#(5, string.length(text) + 2))

    // Operators (index 6) — only real operators, not punctuation
    token.SymbolPipe -> Ok(#(6, 1))
    token.SymbolDotDot -> Ok(#(6, 2))
    token.SymbolEquals -> Ok(#(6, 1))
    token.SymbolPlus -> Ok(#(6, 1))

    // Skip punctuation (: and * handled by TextMate), whitespace, braces, parens, brackets, comma, EOF
    _ -> Error(Nil)
  }
}
