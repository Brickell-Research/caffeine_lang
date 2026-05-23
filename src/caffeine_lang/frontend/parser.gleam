import caffeine_lang/frontend/ast.{
  type Comment, type ExpectItem, type ExpectsFile, type Extendable,
  type ExtendableKind, type Field, type Literal, type MeasurementItem,
  type MeasurementsFile, type Parsed, type Struct, type TypeAlias,
}
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer
import caffeine_lang/types.{
  type ParsedType, type PrimitiveTypes, type RefinementTypes, Boolean, Defaulted,
  Dict, Float, InclusiveRange, Integer, List, NumericType, OneOf, Optional,
  ParsedCollection, ParsedModifier, ParsedPrimitive, ParsedRecord,
  ParsedRefinement, ParsedTypeAliasRef, Percentage, SemanticType,
  String as StringType, URL,
}
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string

/// Parser state tracking position in token stream.
type ParserState {
  ParserState(
    tokens: List(PositionedToken),
    line: Int,
    column: Int,
    prev_line: Int,
    prev_column: Int,
  )
}

/// Parses a measurements file from source text.
/// Returns all recoverable parse errors rather than stopping at the first one.
pub fn parse_measurements_file(
  source: String,
) -> Result(MeasurementsFile(Parsed), List(ParserError)) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(fn(e) { [parser_error.TokenizerError(e)] }),
  )
  let filtered = filter_whitespace(tokens)
  let state = init_state(filtered)
  let #(pending, state) = consume_comments(state)
  use #(type_aliases, pending, state) <- result.try(
    parse_type_aliases(state, pending)
    |> result.map_error(fn(e) { [e] }),
  )
  use #(extendables, pending, state) <- result.try(
    parse_extendables(state, pending)
    |> result.map_error(fn(e) { [e] }),
  )
  let #(items, errors, pending, _state) =
    parse_measurement_items_recovering(state, pending)
  case errors {
    [] ->
      Ok(ast.MeasurementsFile(
        type_aliases:,
        extendables:,
        items:,
        trailing_comments: pending,
      ))
    errs -> Error(errs)
  }
}

/// Parses an expects file from source text.
/// Returns all recoverable parse errors rather than stopping at the first one.
pub fn parse_expects_file(
  source: String,
) -> Result(ExpectsFile(Parsed), List(ParserError)) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(fn(e) { [parser_error.TokenizerError(e)] }),
  )
  let filtered = filter_whitespace(tokens)
  let state = init_state(filtered)
  let #(pending, state) = consume_comments(state)
  use #(extendables, pending, state) <- result.try(
    parse_extendables(state, pending)
    |> result.map_error(fn(e) { [e] }),
  )
  let #(items, errors, pending, _state) =
    parse_expect_items_recovering(state, pending)
  case errors {
    [] -> Ok(ast.ExpectsFile(extendables:, items:, trailing_comments: pending))
    errs -> Error(errs)
  }
}

/// Filter out whitespace tokens (keep comments in stream).
fn filter_whitespace(tokens: List(PositionedToken)) -> List(PositionedToken) {
  list.filter(tokens, fn(ptok) {
    case ptok {
      token.PositionedToken(token.WhitespaceNewline, _, _)
      | token.PositionedToken(token.WhitespaceIndent(_), _, _) -> False
      _ -> True
    }
  })
}

/// Consume consecutive comment tokens from the stream, returning them as Comment list.
fn consume_comments(state: ParserState) -> #(List(Comment), ParserState) {
  consume_comments_loop(state, [])
}

fn consume_comments_loop(
  state: ParserState,
  acc: List(Comment),
) -> #(List(Comment), ParserState) {
  case peek(state) {
    token.CommentLine(text) ->
      consume_comments_loop(advance(state), [ast.LineComment(text), ..acc])
    token.CommentSection(text) ->
      consume_comments_loop(advance(state), [ast.SectionComment(text), ..acc])
    token.CommentDoc(text) ->
      consume_comments_loop(advance(state), [ast.DocComment(text), ..acc])
    _ -> #(list.reverse(acc), state)
  }
}

/// Initialize parser state from a list of positioned tokens.
fn init_state(tokens: List(PositionedToken)) -> ParserState {
  case tokens {
    [token.PositionedToken(_, line, column), ..] ->
      ParserState(tokens:, line:, column:, prev_line: line, prev_column: column)
    [] -> ParserState(tokens:, line: 1, column: 1, prev_line: 1, prev_column: 1)
  }
}

/// Peek at the current token without consuming it.
fn peek(state: ParserState) -> Token {
  case state.tokens {
    [token.PositionedToken(tok, _, _), ..] -> tok
    [] -> token.EOF
  }
}

/// Consume current token and advance state.
fn advance(state: ParserState) -> ParserState {
  case state.tokens {
    [_, ..rest] ->
      case rest {
        [token.PositionedToken(_, line, column), ..] ->
          ParserState(
            tokens: rest,
            line:,
            column:,
            prev_line: state.line,
            prev_column: state.column,
          )
        [] ->
          ParserState(
            ..state,
            tokens: rest,
            prev_line: state.line,
            prev_column: state.column,
          )
      }
    [] -> state
  }
}

/// Expect a specific token, consuming it if matched.
fn expect(
  state: ParserState,
  expected: Token,
  expected_name: String,
) -> Result(ParserState, ParserError) {
  case peek(state) {
    tok if tok == expected -> Ok(advance(state))
    tok ->
      Error(parser_error.UnexpectedToken(
        expected_name,
        token.to_string(tok),
        state.prev_line,
        state.prev_column,
      ))
  }
}

// =============================================================================
// TYPE ALIASES
// =============================================================================

/// Parse zero or more type aliases at file start.
/// Type alias syntax: _name (Type): <refinement_type>
fn parse_type_aliases(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(TypeAlias), List(Comment), ParserState), ParserError) {
  parse_type_aliases_loop(state, [], pending)
}

fn parse_type_aliases_loop(
  state: ParserState,
  acc: List(TypeAlias),
  pending: List(Comment),
) -> Result(#(List(TypeAlias), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      // Check if this is a type alias by peeking ahead for (Type)
      case is_type_alias(state) {
        True -> {
          use #(type_alias, state) <- result.try(parse_type_alias(
            state,
            name,
            pending,
          ))
          let #(next_pending, state) = consume_comments(state)
          parse_type_aliases_loop(state, [type_alias, ..acc], next_pending)
        }
        False -> Ok(#(list.reverse(acc), pending, state))
      }
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
  }
}

/// Check if current position is a type alias definition.
/// Looks for pattern: Identifier ( KeywordType )
fn is_type_alias(state: ParserState) -> Bool {
  case state.tokens {
    [
      token.PositionedToken(token.Identifier(_), _, _),
      token.PositionedToken(token.SymbolLeftParen, _, _),
      token.PositionedToken(token.KeywordType, _, _),
      ..
    ] -> True
    _ -> False
  }
}

fn parse_type_alias(
  state: ParserState,
  name: String,
  leading_comments: List(Comment),
) -> Result(#(TypeAlias, ParserState), ParserError) {
  // Validate type alias name - must be more than just underscore
  case name {
    "_" ->
      Error(parser_error.InvalidTypeAliasName(
        name,
        "type alias name must have at least one character after the underscore",
        state.line,
        state.column,
      ))
    _ -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolLeftParen, "("))
      // Expect "Type" identifier
      case peek(state) {
        token.KeywordType -> {
          let state = advance(state)
          use state <- result.try(expect(state, token.SymbolRightParen, ")"))
          use state <- result.try(expect(state, token.SymbolColon, ":"))
          // Parse the refinement type - must be a refined primitive type
          use #(type_, state) <- result.try(parse_type(state))
          Ok(#(ast.TypeAlias(name:, type_:, leading_comments:), state))
        }
        tok ->
          Error(parser_error.UnexpectedToken(
            "Type",
            token.to_string(tok),
            state.line,
            state.column,
          ))
      }
    }
  }
}

// =============================================================================
// EXTENDABLES
// =============================================================================

/// Parse zero or more extendables at file start.
fn parse_extendables(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(Extendable), List(Comment), ParserState), ParserError) {
  parse_extendables_loop(state, [], pending)
}

fn parse_extendables_loop(
  state: ParserState,
  acc: List(Extendable),
  pending: List(Comment),
) -> Result(#(List(Extendable), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      use #(extendable, state) <- result.try(parse_extendable(
        state,
        name,
        pending,
      ))
      let #(next_pending, state) = consume_comments(state)
      parse_extendables_loop(state, [extendable, ..acc], next_pending)
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
  }
}

fn parse_extendable(
  state: ParserState,
  name: String,
  leading_comments: List(Comment),
) -> Result(#(Extendable, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(kind, state) <- result.try(parse_extendable_kind(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  // Parse body based on kind: Requires has types, Provides has literals.
  use #(body, state) <- result.try(case kind {
    ast.ExtendableRequires -> parse_type_struct(state)
    ast.ExtendableProvides -> parse_literal_struct(state)
  })
  Ok(#(ast.Extendable(name:, kind:, body:, leading_comments:), state))
}

fn parse_extendable_kind(
  state: ParserState,
) -> Result(#(ExtendableKind, ParserState), ParserError) {
  case peek(state) {
    token.KeywordRequires -> Ok(#(ast.ExtendableRequires, advance(state)))
    token.KeywordProvides -> Ok(#(ast.ExtendableProvides, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "Type, Requires, or Provides",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// MEASUREMENT ITEMS
// =============================================================================

fn parse_measurement_item(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(MeasurementItem, ParserState), ParserError) {
  use #(name, state) <- result.try(parse_string_literal(state))
  use #(expectation_type, state) <- result.try(parse_optional_expectation_type(
    state,
  ))
  use #(extends, state) <- result.try(parse_optional_extends(state))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  let #(_pending, state) = consume_comments(state)
  // `Requires {}` is optional — measurements with no params can skip it
  // entirely and jump straight to `Provides`.
  use #(requires, state) <- result.try(case peek(state) {
    token.KeywordRequires -> {
      let state = advance(state)
      parse_type_struct(state)
    }
    _ -> Ok(#(ast.Struct(fields: [], trailing_comments: []), state))
  })
  let #(_pending, state) = consume_comments(state)
  use state <- result.try(expect(state, token.KeywordProvides, "Provides"))
  use #(provides, state) <- result.try(parse_literal_struct(state))
  Ok(#(
    ast.MeasurementItem(
      name:,
      expectation_type:,
      extends:,
      requires:,
      provides:,
      leading_comments:,
    ),
    state,
  ))
}

/// Recognises an optional `success_rate` or `time_slice` keyword in the
/// measurement header, e.g. `"api" success_rate:` or `"api" time_slice:`.
/// Returns None if the next token is `:` or `extends` (legacy untyped header).
fn parse_optional_expectation_type(
  state: ParserState,
) -> Result(#(option.Option(ast.ExpectationType), ParserState), ParserError) {
  case peek(state) {
    token.KeywordSuccessRate ->
      Ok(#(option.Some(ast.SuccessRateType), advance(state)))
    token.KeywordTimeSlice ->
      Ok(#(option.Some(ast.TimeSliceType), advance(state)))
    _ -> Ok(#(option.None, state))
  }
}

// =============================================================================
// EXPECT ITEMS
// =============================================================================

/// Parses a single standalone expectation:
///
///   "<name>" (extends [...])?:
///     (Assumes:
///        (hard|soft) dependency on "<target>"
///        ...)?
///     Guarantees <pct>% (below <dur>)? over <dur> window
///       (as measured by "<measurement>" with: { <fields> })?
fn parse_expect_item(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(ExpectItem, ParserState), ParserError) {
  use #(name, state) <- result.try(parse_string_literal(state))
  use #(extends, state) <- result.try(parse_optional_extends(state))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  let #(_pending, state) = consume_comments(state)
  use #(assumes, state) <- result.try(parse_optional_assumes(state))
  use #(guarantees, state) <- result.try(parse_guarantees(state))
  Ok(#(
    ast.ExpectItem(name:, extends:, assumes:, guarantees:, leading_comments:),
    state,
  ))
}

fn parse_optional_assumes(
  state: ParserState,
) -> Result(#(option.Option(ast.Assumes), ParserState), ParserError) {
  case peek(state) {
    token.KeywordAssumes -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      let #(pending, state) = consume_comments(state)
      use #(deps, trailing, state) <- result.try(
        parse_dependency_lines(state, pending, []),
      )
      Ok(#(option.Some(ast.Assumes(deps:, trailing_comments: trailing)), state))
    }
    _ -> Ok(#(option.None, state))
  }
}

fn parse_dependency_lines(
  state: ParserState,
  leading: List(Comment),
  acc: List(ast.Dependency),
) -> Result(#(List(ast.Dependency), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.KeywordHard | token.KeywordSoft -> {
      use #(dep, state) <- result.try(parse_dependency_line(state, leading))
      let #(next_pending, state) = consume_comments(state)
      parse_dependency_lines(state, next_pending, [dep, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), leading, state))
  }
}

fn parse_dependency_line(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(ast.Dependency, ParserState), ParserError) {
  use #(kind, state) <- result.try(case peek(state) {
    token.KeywordHard -> Ok(#(ast.HardDep, advance(state)))
    token.KeywordSoft -> Ok(#(ast.SoftDep, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "hard or soft",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  })
  use state <- result.try(expect(state, token.KeywordDependency, "dependency"))
  use state <- result.try(expect(state, token.KeywordOn, "on"))
  use #(target, state) <- result.try(parse_string_literal(state))
  Ok(#(ast.Dependency(kind:, target:, leading_comments:), state))
}

fn parse_guarantees(
  state: ParserState,
) -> Result(#(ast.Guarantees, ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordGuarantees, "Guarantees"))
  use #(threshold, state) <- result.try(parse_percentage_literal(state))
  use #(below, state) <- result.try(parse_optional_below(state))
  use state <- result.try(expect(state, token.KeywordOver, "over"))
  use #(window, state) <- result.try(parse_duration_literal(state))
  use state <- result.try(expect(state, token.KeywordWindow, "window"))
  use #(measured_by, state) <- result.try(parse_optional_measured_by(state))
  Ok(#(ast.Guarantees(threshold:, below:, window:, measured_by:), state))
}

fn parse_optional_below(
  state: ParserState,
) -> Result(#(option.Option(ast.DurationLiteral), ParserState), ParserError) {
  case peek(state) {
    token.KeywordBelow -> {
      let state = advance(state)
      use #(dur, state) <- result.try(parse_duration_literal(state))
      Ok(#(option.Some(dur), state))
    }
    _ -> Ok(#(option.None, state))
  }
}

fn parse_optional_measured_by(
  state: ParserState,
) -> Result(#(option.Option(ast.MeasuredBy), ParserState), ParserError) {
  case peek(state) {
    token.KeywordAs -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.KeywordMeasured, "measured"))
      use state <- result.try(expect(state, token.KeywordBy, "by"))
      use #(measurement, state) <- result.try(parse_string_literal(state))
      use state <- result.try(expect(state, token.KeywordWith, "with"))
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(with_args, state) <- result.try(parse_literal_struct(state))
      Ok(#(option.Some(ast.MeasuredBy(measurement:, with_args:)), state))
    }
    _ -> Ok(#(option.None, state))
  }
}

fn parse_percentage_literal(
  state: ParserState,
) -> Result(#(Float, ParserState), ParserError) {
  case peek(state) {
    token.LiteralPercentage(f) -> Ok(#(f, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "percentage (e.g. 99.9%)",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_duration_literal(
  state: ParserState,
) -> Result(#(ast.DurationLiteral, ParserState), ParserError) {
  case peek(state) {
    token.LiteralDuration(amount, unit) ->
      Ok(#(ast.DurationLiteral(amount:, unit:), advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "duration (e.g. 10d, 50ms)",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// ERROR RECOVERY
// =============================================================================

/// Advance the state until `peek(state)` satisfies `predicate`.
/// Used by recovery loops to resync to the next item/block boundary.
fn skip_until(state: ParserState, predicate: fn(Token) -> Bool) -> ParserState {
  case predicate(peek(state)) {
    True -> state
    False -> skip_until(advance(state), predicate)
  }
}

fn at_expect_item_boundary(tok: Token) -> Bool {
  case tok {
    token.LiteralString(_) | token.EOF -> True
    _ -> False
  }
}

fn at_measurement_item_boundary(tok: Token) -> Bool {
  case tok {
    token.LiteralString(_) | token.EOF -> True
    _ -> False
  }
}

/// Parse measurement items with recovery between items.
/// Measurement items start with a string literal name.
fn parse_measurement_items_recovering(
  state: ParserState,
  pending: List(Comment),
) -> #(List(MeasurementItem), List(ParserError), List(Comment), ParserState) {
  measurement_items_loop(state, [], [], pending)
}

fn measurement_items_loop(
  state: ParserState,
  items: List(MeasurementItem),
  errors: List(ParserError),
  pending: List(Comment),
) -> #(List(MeasurementItem), List(ParserError), List(Comment), ParserState) {
  case peek(state) {
    token.LiteralString(_) -> {
      case parse_measurement_item(state, pending) {
        Ok(#(item, state)) -> {
          let #(next_pending, state) = consume_comments(state)
          measurement_items_loop(state, [item, ..items], errors, next_pending)
        }
        Error(err) -> {
          let state = skip_until(advance(state), at_measurement_item_boundary)
          let #(next_pending, state) = consume_comments(state)
          measurement_items_loop(state, items, [err, ..errors], next_pending)
        }
      }
    }
    _ -> #(list.reverse(items), list.reverse(errors), pending, state)
  }
}

/// Parse expect items with recovery between items.
/// Each expect item starts with a string literal name (top-level, no grouping).
fn parse_expect_items_recovering(
  state: ParserState,
  pending: List(Comment),
) -> #(List(ExpectItem), List(ParserError), List(Comment), ParserState) {
  expect_items_loop(state, [], [], pending)
}

fn expect_items_loop(
  state: ParserState,
  items: List(ExpectItem),
  errors: List(ParserError),
  pending: List(Comment),
) -> #(List(ExpectItem), List(ParserError), List(Comment), ParserState) {
  case peek(state) {
    token.LiteralString(_) -> {
      case parse_expect_item(state, pending) {
        Ok(#(item, state)) -> {
          let #(next_pending, state) = consume_comments(state)
          expect_items_loop(state, [item, ..items], errors, next_pending)
        }
        Error(err) -> {
          let state = skip_until(advance(state), at_expect_item_boundary)
          let #(next_pending, state) = consume_comments(state)
          expect_items_loop(state, items, [err, ..errors], next_pending)
        }
      }
    }
    _ -> #(list.reverse(items), list.reverse(errors), pending, state)
  }
}

// =============================================================================
// SHARED PARSING
// =============================================================================

fn parse_string_literal(
  state: ParserState,
) -> Result(#(String, ParserState), ParserError) {
  case peek(state) {
    token.LiteralString(s) -> Ok(#(s, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "string",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_optional_extends(
  state: ParserState,
) -> Result(#(List(String), ParserState), ParserError) {
  case peek(state) {
    token.KeywordExtends -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolLeftBracket, "["))
      use #(extends, state) <- result.try(parse_extends_list(state))
      use state <- result.try(expect(state, token.SymbolRightBracket, "]"))
      Ok(#(extends, state))
    }
    _ -> Ok(#([], state))
  }
}

fn parse_extends_list(
  state: ParserState,
) -> Result(#(List(String), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBracket -> Ok(#([], state))
    _ -> {
      use #(first, state) <- result.try(parse_identifier(state))
      sep_by_comma(state, [first], parse_identifier)
    }
  }
}

fn parse_identifier(
  state: ParserState,
) -> Result(#(String, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> Ok(#(name, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "identifier",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

/// Consume `, item , item ...` until a non-comma token. Does not allow
/// trailing commas (the parse_one callback runs after every comma).
fn sep_by_comma(
  state: ParserState,
  acc: List(a),
  parse_one: fn(ParserState) -> Result(#(a, ParserState), ParserError),
) -> Result(#(List(a), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      use #(item, state) <- result.try(parse_one(state))
      sep_by_comma(state, [item, ..acc], parse_one)
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

// =============================================================================
// STRUCT PARSING (shared by Requires and Provides)
// =============================================================================

/// Type alias for a field value parser function.
type FieldValueParser(a) =
  fn(ParserState) -> Result(#(a, ParserState), ParserError)

/// Parses a struct with typed fields (for Requires blocks).
fn parse_type_struct(
  state: ParserState,
) -> Result(#(Struct, ParserState), ParserError) {
  parse_struct(state, fn(s) {
    use #(type_, s) <- result.try(parse_type(s))
    Ok(#(ast.TypeValue(type_), s))
  })
}

/// Parses a struct with literal fields (for Provides blocks).
fn parse_literal_struct(
  state: ParserState,
) -> Result(#(Struct, ParserState), ParserError) {
  parse_struct(state, fn(s) {
    use #(literal, s) <- result.try(parse_literal(s))
    Ok(#(ast.LiteralValue(literal), s))
  })
}

/// Generic struct parser parameterized by field value parser.
fn parse_struct(
  state: ParserState,
  parse_value: FieldValueParser(ast.Value),
) -> Result(#(Struct, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  let #(pending, state) = consume_comments(state)
  use #(fields, trailing_comments, state) <- result.try(parse_fields(
    state,
    pending,
    parse_value,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.Struct(fields:, trailing_comments:), state))
}

fn parse_fields(
  state: ParserState,
  pending: List(Comment),
  parse_value: FieldValueParser(ast.Value),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBrace -> Ok(#([], pending, state))
    token.Identifier(_) -> {
      use #(field, state) <- result.try(parse_field(state, pending, parse_value))
      let #(next_pending, state) = consume_comments(state)
      parse_fields_loop(state, [field], next_pending, parse_value)
    }
    // Helpful error for JSON-style quoted field names
    token.LiteralString(name) ->
      Error(parser_error.QuotedFieldName(name, state.line, state.column))
    tok ->
      Error(parser_error.UnexpectedToken(
        "field name or }",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_fields_loop(
  state: ParserState,
  acc: List(Field),
  pending: List(Comment),
  parse_value: FieldValueParser(ast.Value),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      let #(next_pending, state) = consume_comments(state)
      // Allow trailing comma
      case peek(state) {
        token.SymbolRightBrace -> Ok(#(list.reverse(acc), next_pending, state))
        _ -> {
          use #(field, state) <- result.try(parse_field(
            state,
            next_pending,
            parse_value,
          ))
          let #(next_pending, state) = consume_comments(state)
          parse_fields_loop(state, [field, ..acc], next_pending, parse_value)
        }
      }
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
  }
}

fn parse_field(
  state: ParserState,
  leading_comments: List(Comment),
  parse_value: FieldValueParser(ast.Value),
) -> Result(#(Field, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(value, state) <- result.try(parse_value(state))
      Ok(#(ast.Field(name:, value:, leading_comments:), state))
    }
    // Helpful error for JSON-style quoted field names
    token.LiteralString(name) ->
      Error(parser_error.QuotedFieldName(name, state.line, state.column))
    tok ->
      Error(parser_error.UnexpectedToken(
        "field name",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// TYPES
// =============================================================================

/// Match a primitive type keyword and consume it. Returns Error(Nil) on miss.
fn try_parse_primitive_keyword(
  state: ParserState,
) -> Result(#(PrimitiveTypes, ParserState), Nil) {
  case peek(state) {
    token.KeywordString -> Ok(#(StringType, advance(state)))
    token.KeywordInteger -> Ok(#(NumericType(Integer), advance(state)))
    token.KeywordFloat -> Ok(#(NumericType(Float), advance(state)))
    token.KeywordBoolean -> Ok(#(Boolean, advance(state)))
    token.KeywordURL -> Ok(#(SemanticType(URL), advance(state)))
    token.KeywordPercentage -> Ok(#(NumericType(Percentage), advance(state)))
    _ -> Error(Nil)
  }
}

/// Parse a type-alias reference (`_name`) or surface UnknownType for a bare identifier.
fn parse_type_alias_ref_or_error(
  state: ParserState,
  name: String,
) -> Result(#(ParsedType, ParserState), ParserError) {
  case string.starts_with(name, "_") {
    True -> Ok(#(ParsedTypeAliasRef(name), advance(state)))
    False -> Error(parser_error.UnknownType(name, state.line, state.column))
  }
}

fn parse_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  case try_parse_primitive_keyword(state) {
    Ok(#(primitive, state)) ->
      case peek(state) {
        token.SymbolLeftBrace -> {
          use #(refinement, state) <- result.try(parse_refinement(
            state,
            primitive,
          ))
          Ok(#(ParsedRefinement(refinement), state))
        }
        _ -> Ok(#(ParsedPrimitive(primitive), state))
      }
    Error(_) ->
      case peek(state) {
        token.KeywordList -> parse_list_type(state)
        token.KeywordDict -> parse_dict_type(state)
        token.KeywordOptional -> parse_optional_type(state)
        token.KeywordDefaulted -> parse_defaulted_type(state)
        token.SymbolLeftBrace -> parse_record_type(state)
        token.Identifier(name) -> parse_type_alias_ref_or_error(state, name)
        tok ->
          Error(parser_error.UnknownType(
            token.to_string(tok),
            state.line,
            state.column,
          ))
      }
  }
}

/// Parses a record type: `{ field: Type, ... }`.
/// Reuses parse_type_struct to parse the struct, then converts fields to a dict.
fn parse_record_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  use #(s, state) <- result.try(parse_type_struct(state))
  let fields =
    s.fields
    |> list.map(fn(field) {
      let assert ast.TypeValue(t) = field.value
      #(field.name, t)
    })
    |> dict.from_list
  Ok(#(ParsedRecord(fields), state))
}

/// Parses types valid inside collections: primitives, nested collections, or type alias refs.
/// Does not allow modifiers (Optional/Defaulted) or refinements directly.
fn parse_collection_inner_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  case try_parse_primitive_keyword(state) {
    Ok(#(primitive, state)) -> Ok(#(ParsedPrimitive(primitive), state))
    Error(_) ->
      case peek(state) {
        token.KeywordList -> parse_list_type(state)
        token.KeywordDict -> parse_dict_type(state)
        token.SymbolLeftBrace -> parse_record_type(state)
        token.Identifier(name) -> parse_type_alias_ref_or_error(state, name)
        tok ->
          Error(parser_error.UnknownType(
            token.to_string(tok),
            state.line,
            state.column,
          ))
      }
  }
}

fn parse_list_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(element, state) <- result.try(parse_collection_inner_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(ParsedCollection(List(element)), state))
}

fn parse_dict_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  // Dict keys must be String primitive or type alias ref (for JSON compatibility)
  use #(key, state) <- result.try(parse_dict_key_type(state))
  use state <- result.try(expect(state, token.SymbolComma, ","))
  // Dict values can be primitives, nested collections, or type alias refs
  use #(value, state) <- result.try(parse_collection_inner_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(ParsedCollection(Dict(key, value)), state))
}

/// Parses types valid as Dict keys: String primitive or type alias ref.
/// Only String is allowed as a primitive key (JSON keys must be strings).
fn parse_dict_key_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString -> Ok(#(ParsedPrimitive(StringType), advance(state)))
    token.Identifier(name) -> parse_type_alias_ref_or_error(state, name)
    tok ->
      Error(parser_error.UnknownType(
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_optional_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(inner, state) <- result.try(parse_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(ParsedModifier(Optional(inner)), state))
}

fn parse_defaulted_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(inner, state) <- result.try(parse_type(state))
  use state <- result.try(expect(state, token.SymbolComma, ","))
  use #(default, state) <- result.try(parse_literal(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  let defaulted = ParsedModifier(Defaulted(inner, literal_to_string(default)))
  // Check for optional refinement: Defaulted(String, "x") { x | x in { ... } }
  case peek(state) {
    token.SymbolLeftBrace -> {
      use #(refinement, state) <- result.try(parse_refinement_with_inner(
        state,
        defaulted,
      ))
      Ok(#(ParsedRefinement(refinement), state))
    }
    _ -> Ok(#(defaulted, state))
  }
}

// =============================================================================
// REFINEMENTS
// =============================================================================

/// Parse `{ x | x in <body> }` for a primitive base type.
fn parse_refinement(
  state: ParserState,
  primitive: PrimitiveTypes,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
  parse_refinement_with_inner(state, ParsedPrimitive(primitive))
}

/// Parse `{ x | x in <body> }` wrapping an arbitrary inner type. Shared
/// implementation for primitive refinements and Defaulted-with-refinement.
fn parse_refinement_with_inner(
  state: ParserState,
  inner: ParsedType,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.SymbolPipe, "|"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.KeywordIn, "in"))
  use #(refinement, state) <- result.try(parse_refinement_body(state, inner))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(refinement, state))
}

fn expect_x(state: ParserState) -> Result(ParserState, ParserError) {
  case peek(state) {
    token.KeywordX -> Ok(advance(state))
    tok ->
      Error(parser_error.InvalidRefinement(
        "expected 'x', got " <> token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_refinement_body(
  state: ParserState,
  inner: ParsedType,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
      let string_values = list.map(values, literal_to_string)
      Ok(#(OneOf(inner, set.from_list(string_values)), state))
    }
    // Range: ( min..max )
    token.SymbolLeftParen -> {
      let state = advance(state)
      use #(min, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolDotDot, ".."))
      use #(max, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolRightParen, ")"))
      Ok(#(
        InclusiveRange(inner, literal_to_string(min), literal_to_string(max)),
        state,
      ))
    }
    tok ->
      Error(parser_error.UnexpectedToken(
        "{ or (",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// LITERALS
// =============================================================================

fn parse_literal(
  state: ParserState,
) -> Result(#(Literal, ParserState), ParserError) {
  case peek(state) {
    token.LiteralString(s) -> Ok(#(ast.LiteralString(s), advance(state)))
    token.LiteralInteger(n) -> Ok(#(ast.LiteralInteger(n), advance(state)))
    token.LiteralFloat(f) -> Ok(#(ast.LiteralFloat(f), advance(state)))
    token.LiteralPercentage(f) ->
      Ok(#(ast.LiteralPercentage(f), advance(state)))
    token.LiteralDuration(amount, unit) ->
      Ok(#(ast.LiteralDuration(amount, unit), advance(state)))
    token.LiteralTrue -> Ok(#(ast.LiteralTrue, advance(state)))
    token.LiteralFalse -> Ok(#(ast.LiteralFalse, advance(state)))
    token.SymbolLeftBracket -> parse_literal_list(state)
    token.SymbolLeftBrace -> parse_literal_struct_value(state)
    token.KeywordFrom -> parse_external_indicator(state)
    tok ->
      Error(parser_error.UnexpectedToken(
        "literal value",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// EXTERNAL INDICATORS
// =============================================================================
//
// Surface forms supported:
//
//   single-line (count of matching events):
//     from <source> where <field> = <literal> [and <field> = <literal>]...
//
//   block (with value extraction):
//     from <source> {
//       where: <field> = <literal> [and <field> = <literal>]...
//       value: <path> as <type>
//     }
//
// The block form's `value:` line is optional; omitting it produces the same
// shape as the single-line form. Field names inside match clauses are
// identifiers; literal RHS values support template variables (e.g. `"$$->v$$"`)
// because they round-trip through the normal literal parser.

/// Parse a `from <source> ...` external-indicator literal. Dispatches on the
/// token after the source identifier: `{` opens the block form, `where`
/// starts the single-line form.
fn parse_external_indicator(
  state: ParserState,
) -> Result(#(Literal, ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordFrom, "from"))
  use #(source, state) <- result.try(parse_identifier(state))
  case peek(state) {
    token.SymbolLeftBrace -> parse_external_indicator_block(state, source)
    token.KeywordWhere -> {
      use #(match, state) <- result.try(parse_where_chain(state))
      Ok(#(ast.LiteralExternalIndicator(source, match, option.None), state))
    }
    tok ->
      Error(parser_error.UnexpectedToken(
        "`where` or `{` after `from " <> source <> "`",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

/// Parse `{ where: <chain> [value: <path> as <type>] }`. Requires `where:`
/// to come first; `value:` is optional. The block form is what enables
/// value extraction; the single-line form is sugar for the where-only case.
fn parse_external_indicator_block(
  state: ParserState,
  source: String,
) -> Result(#(Literal, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  use state <- result.try(expect(state, token.KeywordWhere, "where"))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  use #(match, state) <- result.try(parse_match_chain(state))
  use #(value_extraction, state) <- result.try(parse_optional_value_extraction(
    state,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.LiteralExternalIndicator(source, match, value_extraction), state))
}

/// Parse a `where <chain>` clause: consumes `where`, then one or more
/// `and`-separated match clauses. Used by the single-line surface form.
fn parse_where_chain(
  state: ParserState,
) -> Result(#(List(ast.MatchClause), ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordWhere, "where"))
  parse_match_chain(state)
}

/// Parse a chain of one or more match clauses separated by `and`. Stops at
/// the first non-`and` token. Returns the chain in source order.
fn parse_match_chain(
  state: ParserState,
) -> Result(#(List(ast.MatchClause), ParserState), ParserError) {
  use #(first, state) <- result.try(parse_match_clause(state))
  parse_match_chain_loop(state, [first])
}

fn parse_match_chain_loop(
  state: ParserState,
  acc: List(ast.MatchClause),
) -> Result(#(List(ast.MatchClause), ParserState), ParserError) {
  case peek(state) {
    token.KeywordAnd -> {
      let state = advance(state)
      use #(clause, state) <- result.try(parse_match_clause(state))
      parse_match_chain_loop(state, [clause, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

/// Parse `<field> = <literal>`. The field name is an identifier; the value
/// is a literal that supports `$$var$$` template interpolation via the
/// normal literal parser.
fn parse_match_clause(
  state: ParserState,
) -> Result(#(ast.MatchClause, ParserState), ParserError) {
  use #(field, state) <- result.try(parse_identifier(state))
  use state <- result.try(expect(state, token.SymbolEquals, "="))
  use #(value, state) <- result.try(parse_literal(state))
  Ok(#(ast.MatchClause(field, value), state))
}

/// Parse `value: <path> as <type>` if present (block form only). Returns
/// None if the next token isn't an Identifier opening the value-extraction
/// line, so callers can fall through to `}`.
fn parse_optional_value_extraction(
  state: ParserState,
) -> Result(#(option.Option(ast.ValueExtraction), ParserState), ParserError) {
  case peek(state) {
    token.Identifier("value") -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(path, state) <- result.try(parse_identifier(state))
      use state <- result.try(expect(state, token.KeywordAs, "as"))
      use #(type_, state) <- result.try(parse_type(state))
      Ok(#(option.Some(ast.ValueExtraction(path, type_)), state))
    }
    _ -> Ok(#(option.None, state))
  }
}

fn parse_literal_list(
  state: ParserState,
) -> Result(#(Literal, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBracket, "["))
  use #(elements, state) <- result.try(parse_literal_list_contents(state))
  use state <- result.try(expect(state, token.SymbolRightBracket, "]"))
  Ok(#(ast.LiteralList(elements), state))
}

fn parse_literal_list_contents(
  state: ParserState,
) -> Result(#(List(Literal), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBracket | token.SymbolRightBrace -> Ok(#([], state))
    _ -> {
      use #(first, state) <- result.try(parse_literal(state))
      sep_by_comma(state, [first], parse_literal)
    }
  }
}

fn parse_literal_struct_value(
  state: ParserState,
) -> Result(#(Literal, ParserState), ParserError) {
  let parse_value = fn(s) {
    use #(literal, s) <- result.try(parse_literal(s))
    Ok(#(ast.LiteralValue(literal), s))
  }
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  let #(pending, state) = consume_comments(state)
  use #(fields, trailing_comments, state) <- result.try(parse_fields(
    state,
    pending,
    parse_value,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.LiteralStruct(fields, trailing_comments), state))
}

/// Convert a Literal to its string representation for use in refinements/defaults.
/// List literals are serialized as "[a, b, c]" using the same element format as
/// types.gleam's value-to-string, so list defaults can be round-tripped at the
/// resolver. Round-trip via comma-split does not preserve commas embedded inside
/// individual string elements.
fn literal_to_string(literal: Literal) -> String {
  case literal {
    ast.LiteralString(s) -> s
    ast.LiteralInteger(n) -> int.to_string(n)
    ast.LiteralFloat(f) -> float.to_string(f)
    ast.LiteralPercentage(f) -> float.to_string(f) <> "%"
    ast.LiteralDuration(amount, unit) -> float.to_string(amount) <> unit
    ast.LiteralTrue -> "true"
    ast.LiteralFalse -> "false"
    ast.LiteralList(elements) ->
      "[" <> elements |> list.map(literal_to_string) |> string.join(", ") <> "]"
    ast.LiteralStruct(_, _) -> "{}"
    // External indicators only appear inside measurement `indicators:` blocks
    // and never inside refinement/default value positions, so this branch is
    // unreachable from real source. A placeholder string keeps the totality
    // check happy.
    ast.LiteralExternalIndicator(source, _, _) -> "<from " <> source <> ">"
  }
}
