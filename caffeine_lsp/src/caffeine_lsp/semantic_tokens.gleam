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
  "property", "function", "modifier",
]

// Token type indices matching the legend above.
const stt_keyword = 0

const stt_type = 1

const stt_string = 2

const stt_number = 3

const stt_variable = 4

const stt_comment = 5

const stt_operator = 6

const stt_property = 7

const stt_function = 8

const stt_modifier = 9

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
          let new_acc = [0, token_type, length, delta_col, delta_line, ..acc]
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
    // Keywords
    token.KeywordExpectations -> Ok(#(stt_keyword, 12))
    token.KeywordMeasured -> Ok(#(stt_keyword, 8))
    token.KeywordBy -> Ok(#(stt_keyword, 2))
    token.KeywordExtends -> Ok(#(stt_keyword, 7))
    token.KeywordRequires -> Ok(#(stt_keyword, 8))
    token.KeywordProvides -> Ok(#(stt_keyword, 8))
    token.KeywordIn -> Ok(#(stt_keyword, 2))
    token.KeywordType -> Ok(#(stt_keyword, 4))

    // Type keywords
    token.KeywordString -> Ok(#(stt_type, 6))
    token.KeywordInteger -> Ok(#(stt_type, 7))
    token.KeywordFloat -> Ok(#(stt_type, 5))
    token.KeywordBoolean -> Ok(#(stt_type, 7))
    token.KeywordURL -> Ok(#(stt_type, 3))
    token.KeywordPercentage -> Ok(#(stt_type, 10))

    // Modifier keywords — collection types and optionality
    token.KeywordList -> Ok(#(stt_modifier, 4))
    token.KeywordDict -> Ok(#(stt_modifier, 4))
    token.KeywordOptional -> Ok(#(stt_modifier, 8))
    token.KeywordDefaulted -> Ok(#(stt_modifier, 9))

    // Boolean literals
    token.LiteralTrue -> Ok(#(stt_keyword, 4))
    token.LiteralFalse -> Ok(#(stt_keyword, 5))

    // String literals — +2 for quotes
    token.LiteralString(s) -> Ok(#(stt_string, string.length(s) + 2))

    // Number literals
    token.LiteralInteger(n) ->
      Ok(#(stt_number, string.length(int.to_string(n))))
    token.LiteralFloat(f) ->
      Ok(#(stt_number, string.length(float.to_string(f))))
    // Percentage literal — +1 for % suffix
    token.LiteralPercentage(f) ->
      Ok(#(stt_number, string.length(float.to_string(f)) + 1))

    // Refinement variable
    token.KeywordX -> Ok(#(stt_variable, 1))

    // Identifiers — context-dependent classification
    token.Identifier(name) -> {
      let len = string.length(name)
      case string.starts_with(name, "_"), next {
        // _extendable followed by ( → function
        True, Ok(token.SymbolLeftParen) -> Ok(#(stt_function, len))
        // _extendable not followed by ( → variable
        True, _ -> Ok(#(stt_variable, len))
        // identifier followed by : → property
        False, Ok(token.SymbolColon) -> Ok(#(stt_property, len))
        // plain identifier → variable
        _, _ -> Ok(#(stt_variable, len))
      }
    }

    // Comments — text excludes the leading # or ##
    token.CommentLine(text) -> Ok(#(stt_comment, string.length(text) + 1))
    token.CommentSection(text) -> Ok(#(stt_comment, string.length(text) + 2))

    // Operators — only real operators, not punctuation
    token.SymbolPipe -> Ok(#(stt_operator, 1))
    token.SymbolDotDot -> Ok(#(stt_operator, 2))
    token.SymbolEquals -> Ok(#(stt_operator, 1))

    // Colon — type annotation operator
    token.SymbolColon -> Ok(#(stt_operator, 1))

    // Skip remaining punctuation, whitespace, braces, parens, brackets, comma, EOF
    _ -> Error(Nil)
  }
}
