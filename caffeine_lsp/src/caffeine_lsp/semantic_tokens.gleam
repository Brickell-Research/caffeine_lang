import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer
import caffeine_lsp/lsp_types.{
  SttComment, SttEnumMember, SttFunction, SttKeyword, SttModifier, SttNumber,
  SttOperator, SttProperty, SttString, SttType, SttVariable,
}
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
  let keyword = lsp_types.semantic_token_type_to_int(SttKeyword)
  let type_ = lsp_types.semantic_token_type_to_int(SttType)
  let str = lsp_types.semantic_token_type_to_int(SttString)
  let number = lsp_types.semantic_token_type_to_int(SttNumber)
  let variable = lsp_types.semantic_token_type_to_int(SttVariable)
  let comment = lsp_types.semantic_token_type_to_int(SttComment)
  let operator = lsp_types.semantic_token_type_to_int(SttOperator)
  let property = lsp_types.semantic_token_type_to_int(SttProperty)
  let function = lsp_types.semantic_token_type_to_int(SttFunction)
  let modifier = lsp_types.semantic_token_type_to_int(SttModifier)
  let _enum_member = lsp_types.semantic_token_type_to_int(SttEnumMember)

  case tok {
    // Keywords
    token.KeywordBlueprints -> Ok(#(keyword, 10))
    token.KeywordExpectations -> Ok(#(keyword, 12))
    token.KeywordFor -> Ok(#(keyword, 3))
    token.KeywordExtends -> Ok(#(keyword, 7))
    token.KeywordRequires -> Ok(#(keyword, 8))
    token.KeywordProvides -> Ok(#(keyword, 8))
    token.KeywordIn -> Ok(#(keyword, 2))
    token.KeywordType -> Ok(#(keyword, 4))

    // Type keywords
    token.KeywordString -> Ok(#(type_, 6))
    token.KeywordInteger -> Ok(#(type_, 7))
    token.KeywordFloat -> Ok(#(type_, 5))
    token.KeywordBoolean -> Ok(#(type_, 7))
    token.KeywordURL -> Ok(#(type_, 3))
    token.KeywordPercentage -> Ok(#(type_, 10))

    // Modifier keywords — collection types and optionality
    token.KeywordList -> Ok(#(modifier, 4))
    token.KeywordDict -> Ok(#(modifier, 4))
    token.KeywordOptional -> Ok(#(modifier, 8))
    token.KeywordDefaulted -> Ok(#(modifier, 9))

    // Boolean literals
    token.LiteralTrue -> Ok(#(keyword, 4))
    token.LiteralFalse -> Ok(#(keyword, 5))

    // String literals — +2 for quotes
    token.LiteralString(s) -> Ok(#(str, string.length(s) + 2))

    // Number literals
    token.LiteralInteger(n) -> Ok(#(number, string.length(int.to_string(n))))
    token.LiteralFloat(f) -> Ok(#(number, string.length(float.to_string(f))))
    // Percentage literal — +1 for % suffix
    token.LiteralPercentage(f) ->
      Ok(#(number, string.length(float.to_string(f)) + 1))

    // Refinement variable
    token.KeywordX -> Ok(#(variable, 1))

    // Identifiers — context-dependent classification
    token.Identifier(name) -> {
      let len = string.length(name)
      case string.starts_with(name, "_"), next {
        // _extendable followed by ( → function
        True, Ok(token.SymbolLeftParen) -> Ok(#(function, len))
        // _extendable not followed by ( → variable
        True, _ -> Ok(#(variable, len))
        // identifier followed by : → property
        False, Ok(token.SymbolColon) -> Ok(#(property, len))
        // plain identifier → variable
        _, _ -> Ok(#(variable, len))
      }
    }

    // Comments — text excludes the leading # or ##
    token.CommentLine(text) -> Ok(#(comment, string.length(text) + 1))
    token.CommentSection(text) -> Ok(#(comment, string.length(text) + 2))

    // Operators — only real operators, not punctuation
    token.SymbolPipe -> Ok(#(operator, 1))
    token.SymbolDotDot -> Ok(#(operator, 2))
    token.SymbolEquals -> Ok(#(operator, 1))
    token.SymbolPlus -> Ok(#(operator, 1))

    // Colon — type annotation operator
    token.SymbolColon -> Ok(#(operator, 1))

    // Skip remaining punctuation, whitespace, braces, parens, brackets, comma, EOF
    _ -> Error(Nil)
  }
}
