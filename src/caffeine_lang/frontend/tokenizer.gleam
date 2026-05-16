import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer_error.{type TokenizerError}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Pops the next codepoint off `s`. Returns ("", "") for empty input — the
/// wrapper below turns that into Error(Nil) so call sites read like the
/// gleam_stdlib `pop_codepoint` they replaced. We split by codepoint
/// instead of grapheme to skip the Intl.Segmenter that turns gleam_stdlib's
/// per-char tokenizing into O(N^2) on JS. Grapheme vs codepoint only differs
/// for combining-mark / ZWJ sequences in string-literal / comment bodies,
/// which we never slice grapheme-by-grapheme — just scan for ASCII terminators.
@external(erlang, "tokenizer_ffi", "pop_codepoint")
@external(javascript, "./tokenizer_ffi.mjs", "pop_codepoint")
fn pop_codepoint_raw(s: String) -> #(String, String)

fn pop_codepoint(s: String) -> Result(#(String, String), Nil) {
  case pop_codepoint_raw(s) {
    #("", _) -> Error(Nil)
    pair -> Ok(pair)
  }
}

/// UTF-16 code unit at index — used by is_digit/is_letter on single-codepoint
/// strings. ASCII chars (digits, letters) have codeunit == codepoint, so a
/// range check on the codeunit is sufficient.
@external(erlang, "tokenizer_ffi", "code_unit_at")
@external(javascript, "./tokenizer_ffi.mjs", "code_unit_at")
fn code_unit_at(s: String, i: Int) -> Int

/// Codeunit length of the just-read token; used for column advance. For
/// ASCII tokens this equals grapheme count; for multi-codepoint chars in
/// string/comment bodies, column reports codeunits instead of graphemes —
/// acceptable tradeoff: gleam_stdlib's string.length walks the whole token
/// via Intl.Segmenter per call, and was ~5–10% of total tokenizer time.
@external(erlang, "tokenizer_ffi", "code_unit_length")
@external(javascript, "./tokenizer_ffi.mjs", "code_unit_length")
fn code_unit_length(s: String) -> Int

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
  case pop_codepoint(state.source) {
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
          case pop_codepoint(rest) {
            Ok(#("#", after_hash)) -> {
              case pop_codepoint(after_hash) {
                Ok(#("#", after_third_hash)) -> {
                  let #(comment_text, remaining) =
                    read_until_newline(after_third_hash)
                  tokenize_loop(
                    advance(
                      state,
                      remaining,
                      3 + code_unit_length(comment_text),
                    ),
                    [
                      token.PositionedToken(
                        token.CommentDoc(comment_text),
                        state.line,
                        state.column,
                      ),
                      ..acc
                    ],
                  )
                }
                _ -> {
                  let #(comment_text, remaining) =
                    read_until_newline(after_hash)
                  tokenize_loop(
                    advance(
                      state,
                      remaining,
                      2 + code_unit_length(comment_text),
                    ),
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
              }
            }
            _ -> {
              let #(comment_text, remaining) = read_until_newline(rest)
              tokenize_loop(
                advance(state, remaining, 1 + code_unit_length(comment_text)),
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
          case read_string(rest, []) {
            Ok(#(str_content, remaining)) ->
              tokenize_loop(
                advance(state, remaining, 2 + code_unit_length(str_content)),
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
        "|" -> emit_token(state, rest, token.SymbolPipe, acc)
        "=" -> emit_token(state, rest, token.SymbolEquals, acc)
        "." -> {
          case pop_codepoint(rest) {
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
            Ok(#(tok, remaining, len)) -> {
              let #(final_tok, final_remaining, final_len) =
                maybe_duration_or_percentage(tok, remaining, len)
              tokenize_loop(advance(state, final_remaining, final_len), [
                token.PositionedToken(final_tok, state.line, state.column),
                ..acc
              ])
            }
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
            Ok(#(tok, remaining, len)) -> {
              let #(final_tok, final_remaining, final_len) =
                maybe_duration_or_percentage(tok, remaining, len)
              tokenize_loop(advance(state, final_remaining, final_len), [
                token.PositionedToken(final_tok, state.line, state.column),
                ..acc
              ])
            }
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
              tokenize_loop(advance(state, remaining, code_unit_length(word)), [
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
  case pop_codepoint(source) {
    Ok(#("\n", rest)) -> skip_empty_lines(rest, count + 1)
    _ -> #(source, count)
  }
}

fn count_indentation(source: String, count: Int) -> #(Int, String) {
  case pop_codepoint(source) {
    Ok(#(" ", rest)) -> count_indentation(rest, count + 1)
    Ok(#("\t", rest)) -> count_indentation(rest, count + 2)
    _ -> #(count, source)
  }
}

fn read_until_newline(source: String) -> #(String, String) {
  read_until_newline_loop(source, [])
}

fn read_until_newline_loop(
  source: String,
  acc: List(String),
) -> #(String, String) {
  case pop_codepoint(source) {
    Ok(#("\n", _)) -> #(string.concat(list.reverse(acc)), source)
    Ok(#(char, rest)) -> read_until_newline_loop(rest, [char, ..acc])
    Error(Nil) -> #(string.concat(list.reverse(acc)), source)
  }
}

fn read_string(
  source: String,
  acc: List(String),
) -> Result(#(String, String), Nil) {
  case pop_codepoint(source) {
    Ok(#("\"", rest)) -> Ok(#(string.concat(list.reverse(acc)), rest))
    Ok(#("\n", _)) -> Error(Nil)
    Ok(#(char, rest)) -> read_string(rest, [char, ..acc])
    Error(Nil) -> Error(Nil)
  }
}

fn read_number(
  source: String,
  prefix: String,
) -> Result(#(Token, String, Int), Nil) {
  let #(digits, remaining) = read_digits(source, prefix)
  case pop_codepoint(remaining) {
    Ok(#(".", after_dot)) -> {
      case pop_codepoint(after_dot) {
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

fn read_digits(source: String, prefix: String) -> #(String, String) {
  let initial = case prefix {
    "" -> []
    p -> [p]
  }
  read_digits_loop(source, initial)
}

fn read_digits_loop(source: String, acc: List(String)) -> #(String, String) {
  case pop_codepoint(source) {
    Ok(#(char, rest)) -> {
      case is_digit(char) {
        True -> read_digits_loop(rest, [char, ..acc])
        False -> #(string.concat(list.reverse(acc)), source)
      }
    }
    Error(Nil) -> #(string.concat(list.reverse(acc)), source)
  }
}

fn parse_integer(
  digits: String,
  remaining: String,
) -> Result(#(Token, String, Int), Nil) {
  case int.parse(digits) {
    Ok(n) -> Ok(#(token.LiteralInteger(n), remaining, code_unit_length(digits)))
    Error(Nil) -> Error(Nil)
  }
}

fn parse_float(
  float_str: String,
  remaining: String,
) -> Result(#(Token, String, Int), Nil) {
  case float.parse(float_str) {
    Ok(f) ->
      Ok(#(token.LiteralFloat(f), remaining, code_unit_length(float_str)))
    Error(Nil) -> Error(Nil)
  }
}

/// Checks if a number token is followed by `%`, converting it to LiteralPercentage.
fn maybe_percentage(
  tok: Token,
  remaining: String,
  len: Int,
) -> #(Token, String, Int) {
  case pop_codepoint(remaining) {
    Ok(#("%", after_percent)) -> {
      let float_val = case tok {
        token.LiteralInteger(n) -> int.to_float(n)
        token.LiteralFloat(f) -> f
        _ -> 0.0
      }
      #(token.LiteralPercentage(float_val), after_percent, len + 1)
    }
    _ -> #(tok, remaining, len)
  }
}

/// Tries to attach a duration unit suffix to a numeric token; falls through to
/// `maybe_percentage` if no unit matches. A duration unit only matches when the
/// character after the suffix is NOT an identifier character — so `10d` is a
/// duration but `10days` is `10` followed by identifier `days`.
fn maybe_duration_or_percentage(
  tok: Token,
  remaining: String,
  len: Int,
) -> #(Token, String, Int) {
  case match_duration_unit(remaining) {
    Ok(#(unit, after_unit, unit_len)) -> {
      let float_val = case tok {
        token.LiteralInteger(n) -> int.to_float(n)
        token.LiteralFloat(f) -> f
        _ -> 0.0
      }
      #(token.LiteralDuration(float_val, unit), after_unit, len + unit_len)
    }
    Error(Nil) -> maybe_percentage(tok, remaining, len)
  }
}

/// Tries to match a duration unit suffix at the start of `source`. The suffix
/// must be followed by a non-identifier character (or end of input) to count.
/// Longest match wins: `ms` is tried before `m`.
fn match_duration_unit(source: String) -> Result(#(String, String, Int), Nil) {
  // Try "ms" before "m" so that `5ms` is milliseconds, not 5-minutes-then-s.
  try_unit(source, "ms")
  |> result.lazy_or(fn() { try_unit(source, "s") })
  |> result.lazy_or(fn() { try_unit(source, "m") })
  |> result.lazy_or(fn() { try_unit(source, "h") })
  |> result.lazy_or(fn() { try_unit(source, "d") })
}

fn try_unit(
  source: String,
  unit: String,
) -> Result(#(String, String, Int), Nil) {
  case string.starts_with(source, unit) {
    False -> Error(Nil)
    True -> {
      let after = string.drop_start(source, code_unit_length(unit))
      case pop_codepoint(after) {
        Error(Nil) -> Ok(#(unit, after, code_unit_length(unit)))
        Ok(#(next, _)) ->
          case is_identifier_char(next) {
            True -> Error(Nil)
            False -> Ok(#(unit, after, code_unit_length(unit)))
          }
      }
    }
  }
}

fn is_digit(char: String) -> Bool {
  let code = code_unit_at(char, 0)
  code >= 48 && code <= 57
}

fn is_identifier_start(char: String) -> Bool {
  is_letter(char) || char == "_"
}

fn is_identifier_char(char: String) -> Bool {
  is_letter(char) || is_digit(char) || char == "_"
}

fn is_letter(char: String) -> Bool {
  let code = code_unit_at(char, 0)
  { code >= 65 && code <= 90 } || { code >= 97 && code <= 122 }
}

fn read_identifier(source: String) -> #(String, String) {
  read_identifier_loop(source, [])
}

fn read_identifier_loop(
  source: String,
  acc: List(String),
) -> #(String, String) {
  case pop_codepoint(source) {
    Ok(#(char, rest)) -> {
      case is_identifier_char(char) {
        True -> read_identifier_loop(rest, [char, ..acc])
        False -> #(string.concat(list.reverse(acc)), source)
      }
    }
    Error(Nil) -> #(string.concat(list.reverse(acc)), source)
  }
}

fn keyword_or_identifier(word: String) -> Token {
  case word {
    "Expectations" -> token.KeywordExpectations
    "Unmeasured" -> token.KeywordUnmeasured
    "measured" -> token.KeywordMeasured
    "by" -> token.KeywordBy
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
    "Percentage" -> token.KeywordPercentage
    "true" -> token.LiteralTrue
    "false" -> token.LiteralFalse
    _ -> token.Identifier(word)
  }
}
