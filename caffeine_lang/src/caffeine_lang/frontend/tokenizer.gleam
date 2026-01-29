import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Internal tokenizer state.
type TokenizerState {
  TokenizerState(source: String, line: Int, column: Int, at_line_start: Bool)
}

/// Tokenizes source text into a list of positioned tokens.
pub fn tokenize(
  source: String,
) -> Result(List(PositionedToken), TokenizerError) {
  let state = TokenizerState(source:, line: 1, column: 1, at_line_start: True)
  tokenize_loop(state, [])
  |> result.map(list.reverse)
}

fn tokenize_loop(
  state: TokenizerState,
  acc: List(PositionedToken),
) -> Result(List(PositionedToken), TokenizerError) {
  case string.pop_grapheme(state.source) {
    Error(Nil) ->
      Ok([token.PositionedToken(token.EOF, state.line, state.column), ..acc])

    Ok(#(char, rest)) -> {
      case char {
        "\n" -> {
          let #(remaining, skipped) = skip_empty_lines(rest, 0)
          let new_state =
            TokenizerState(
              source: remaining,
              line: state.line + 1 + skipped,
              column: 1,
              at_line_start: True,
            )
          tokenize_loop(new_state, [
            token.PositionedToken(
              token.WhitespaceNewline,
              state.line,
              state.column,
            ),
            ..acc
          ])
        }

        // Skip carriage return (handles Windows CRLF line endings)
        "\r" -> tokenize_loop(advance(state, rest, 1), acc)

        " " | "\t" if state.at_line_start -> {
          let #(indent_count, remaining) = count_indentation(state.source, 0)
          tokenize_loop(advance(state, remaining, indent_count), [
            token.PositionedToken(
              token.WhitespaceIndent(indent_count),
              state.line,
              state.column,
            ),
            ..acc
          ])
        }

        " " -> tokenize_loop(advance(state, rest, 1), acc)

        "\t" -> tokenize_loop(advance(state, rest, 2), acc)

        "#" -> {
          case string.pop_grapheme(rest) {
            Ok(#("#", after_hash)) -> {
              let #(comment_text, remaining) = read_until_newline(after_hash)
              tokenize_loop(
                advance(state, remaining, 2 + string.length(comment_text)),
                [
                  token.PositionedToken(
                    token.CommentSection(comment_text),
                    state.line,
                    state.column,
                  ),
                  ..acc
                ],
              )
            }
            _ -> {
              let #(comment_text, remaining) = read_until_newline(rest)
              tokenize_loop(
                advance(state, remaining, 1 + string.length(comment_text)),
                [
                  token.PositionedToken(
                    token.CommentLine(comment_text),
                    state.line,
                    state.column,
                  ),
                  ..acc
                ],
              )
            }
          }
        }

        "\"" -> {
          case read_string(rest, "") {
            Ok(#(str_content, remaining)) ->
              tokenize_loop(
                advance(state, remaining, 2 + string.length(str_content)),
                [
                  token.PositionedToken(
                    token.LiteralString(str_content),
                    state.line,
                    state.column,
                  ),
                  ..acc
                ],
              )
            Error(Nil) ->
              Error(tokenizer_error.UnterminatedString(state.line, state.column))
          }
        }

        "{" -> emit_token(state, rest, token.SymbolLeftBrace, acc)
        "}" -> emit_token(state, rest, token.SymbolRightBrace, acc)
        "(" -> emit_token(state, rest, token.SymbolLeftParen, acc)
        ")" -> emit_token(state, rest, token.SymbolRightParen, acc)
        "[" -> emit_token(state, rest, token.SymbolLeftBracket, acc)
        "]" -> emit_token(state, rest, token.SymbolRightBracket, acc)
        ":" -> emit_token(state, rest, token.SymbolColon, acc)
        "," -> emit_token(state, rest, token.SymbolComma, acc)
        "*" -> emit_token(state, rest, token.SymbolStar, acc)
        "+" -> emit_token(state, rest, token.SymbolPlus, acc)
        "|" -> emit_token(state, rest, token.SymbolPipe, acc)
        "=" -> emit_token(state, rest, token.SymbolEquals, acc)
        "." -> {
          case string.pop_grapheme(rest) {
            Ok(#(".", after_dot)) ->
              emit_token_n(state, after_dot, 2, token.SymbolDotDot, acc)
            _ ->
              Error(tokenizer_error.InvalidCharacter(
                state.line,
                state.column,
                char,
              ))
          }
        }

        "-" -> {
          case read_number(rest, "-") {
            Ok(#(tok, remaining, len)) ->
              tokenize_loop(advance(state, remaining, len), [
                token.PositionedToken(tok, state.line, state.column),
                ..acc
              ])
            Error(Nil) ->
              Error(tokenizer_error.InvalidCharacter(
                state.line,
                state.column,
                "-",
              ))
          }
        }

        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> {
          case read_number(state.source, "") {
            Ok(#(tok, remaining, len)) ->
              tokenize_loop(advance(state, remaining, len), [
                token.PositionedToken(tok, state.line, state.column),
                ..acc
              ])
            Error(Nil) ->
              Error(tokenizer_error.InvalidCharacter(
                state.line,
                state.column,
                char,
              ))
          }
        }

        _ -> {
          case is_identifier_start(char) {
            True -> {
              let #(word, remaining) = read_identifier(state.source)
              tokenize_loop(advance(state, remaining, string.length(word)), [
                token.PositionedToken(
                  keyword_or_identifier(word),
                  state.line,
                  state.column,
                ),
                ..acc
              ])
            }
            False ->
              Error(tokenizer_error.InvalidCharacter(
                state.line,
                state.column,
                char,
              ))
          }
        }
      }
    }
  }
}

fn advance(state: TokenizerState, source: String, len: Int) -> TokenizerState {
  TokenizerState(
    source: source,
    line: state.line,
    column: state.column + len,
    at_line_start: False,
  )
}

fn emit_token(
  state: TokenizerState,
  rest: String,
  tok: Token,
  acc: List(PositionedToken),
) -> Result(List(PositionedToken), TokenizerError) {
  emit_token_n(state, rest, 1, tok, acc)
}

fn emit_token_n(
  state: TokenizerState,
  rest: String,
  len: Int,
  tok: Token,
  acc: List(PositionedToken),
) -> Result(List(PositionedToken), TokenizerError) {
  tokenize_loop(advance(state, rest, len), [
    token.PositionedToken(tok, state.line, state.column),
    ..acc
  ])
}

fn skip_empty_lines(source: String, count: Int) -> #(String, Int) {
  case string.pop_grapheme(source) {
    Ok(#("\n", rest)) -> skip_empty_lines(rest, count + 1)
    _ -> #(source, count)
  }
}

fn count_indentation(source: String, count: Int) -> #(Int, String) {
  case string.pop_grapheme(source) {
    Ok(#(" ", rest)) -> count_indentation(rest, count + 1)
    Ok(#("\t", rest)) -> count_indentation(rest, count + 2)
    _ -> #(count, source)
  }
}

fn read_until_newline(source: String) -> #(String, String) {
  read_until_newline_loop(source, "")
}

fn read_until_newline_loop(source: String, acc: String) -> #(String, String) {
  case string.pop_grapheme(source) {
    Ok(#("\n", _)) -> #(acc, source)
    Ok(#(char, rest)) -> read_until_newline_loop(rest, acc <> char)
    Error(Nil) -> #(acc, source)
  }
}

fn read_string(source: String, acc: String) -> Result(#(String, String), Nil) {
  case string.pop_grapheme(source) {
    Ok(#("\"", rest)) -> Ok(#(acc, rest))
    Ok(#("\n", _)) -> Error(Nil)
    Ok(#(char, rest)) -> read_string(rest, acc <> char)
    Error(Nil) -> Error(Nil)
  }
}

fn read_number(
  source: String,
  prefix: String,
) -> Result(#(Token, String, Int), Nil) {
  let #(digits, remaining) = read_digits(source, prefix)
  case string.pop_grapheme(remaining) {
    Ok(#(".", after_dot)) -> {
      case string.pop_grapheme(after_dot) {
        Ok(#(next_char, _)) if next_char == "." -> {
          parse_integer(digits, remaining)
        }
        Ok(#(next_char, _)) -> {
          case is_digit(next_char) {
            True -> {
              let #(decimal_digits, final_remaining) =
                read_digits(after_dot, "")
              let float_str = digits <> "." <> decimal_digits
              parse_float(float_str, final_remaining)
            }
            False -> parse_integer(digits, remaining)
          }
        }
        Error(Nil) -> parse_integer(digits, remaining)
      }
    }
    _ -> parse_integer(digits, remaining)
  }
}

fn read_digits(source: String, acc: String) -> #(String, String) {
  case string.pop_grapheme(source) {
    Ok(#(char, rest)) -> {
      case is_digit(char) {
        True -> read_digits(rest, acc <> char)
        False -> #(acc, source)
      }
    }
    Error(Nil) -> #(acc, source)
  }
}

fn parse_integer(
  digits: String,
  remaining: String,
) -> Result(#(Token, String, Int), Nil) {
  case int.parse(digits) {
    Ok(n) -> Ok(#(token.LiteralInteger(n), remaining, string.length(digits)))
    Error(Nil) -> Error(Nil)
  }
}

fn parse_float(
  float_str: String,
  remaining: String,
) -> Result(#(Token, String, Int), Nil) {
  case float.parse(float_str) {
    Ok(f) -> Ok(#(token.LiteralFloat(f), remaining, string.length(float_str)))
    Error(Nil) -> Error(Nil)
  }
}

fn is_digit(char: String) -> Bool {
  case string.to_utf_codepoints(char) {
    [cp] -> {
      let code = string.utf_codepoint_to_int(cp)
      code >= 48 && code <= 57
    }
    _ -> False
  }
}

fn is_identifier_start(char: String) -> Bool {
  is_letter(char) || char == "_"
}

fn is_identifier_char(char: String) -> Bool {
  is_letter(char) || is_digit(char) || char == "_"
}

fn is_letter(char: String) -> Bool {
  case string.to_utf_codepoints(char) {
    [cp] -> {
      let code = string.utf_codepoint_to_int(cp)
      { code >= 65 && code <= 90 } || { code >= 97 && code <= 122 }
    }
    _ -> False
  }
}

fn read_identifier(source: String) -> #(String, String) {
  read_identifier_loop(source, "")
}

fn read_identifier_loop(source: String, acc: String) -> #(String, String) {
  case string.pop_grapheme(source) {
    Ok(#(char, rest)) -> {
      case is_identifier_char(char) {
        True -> read_identifier_loop(rest, acc <> char)
        False -> #(acc, source)
      }
    }
    Error(Nil) -> #(acc, source)
  }
}

fn keyword_or_identifier(word: String) -> Token {
  case word {
    "Blueprints" -> token.KeywordBlueprints
    "Expectations" -> token.KeywordExpectations
    "for" -> token.KeywordFor
    "extends" -> token.KeywordExtends
    "Requires" -> token.KeywordRequires
    "Provides" -> token.KeywordProvides
    "in" -> token.KeywordIn
    "x" -> token.KeywordX
    "String" -> token.KeywordString
    "Integer" -> token.KeywordInteger
    "Float" -> token.KeywordFloat
    "Boolean" -> token.KeywordBoolean
    "List" -> token.KeywordList
    "Dict" -> token.KeywordDict
    "Optional" -> token.KeywordOptional
    "Defaulted" -> token.KeywordDefaulted
    "Type" -> token.KeywordType
    "URL" -> token.KeywordURL
    "true" -> token.LiteralTrue
    "false" -> token.LiteralFalse
    _ -> token.Identifier(word)
  }
}
