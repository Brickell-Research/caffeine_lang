import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/common/semantic_types
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsBlock, type BlueprintsFile, type Comment,
  type ExpectItem, type ExpectsBlock, type ExpectsFile, type Extendable,
  type ExtendableKind, type Field, type Literal, type Struct, type TypeAlias,
}
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/token.{type PositionedToken, type Token}
import caffeine_lang/frontend/tokenizer
import gleam/float
import gleam/int
import gleam/list
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

/// Parses a blueprints file from source text.
pub fn parse_blueprints_file(
  source: String,
) -> Result(BlueprintsFile, ParserError) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(parser_error.TokenizerError),
  )
  let filtered = filter_whitespace(tokens)
  let state = init_state(filtered)
  let #(pending, state) = consume_comments(state)
  use #(type_aliases, pending, state) <- result.try(parse_type_aliases(
    state,
    pending,
  ))
  use #(extendables, pending, state) <- result.try(parse_extendables(
    state,
    pending,
  ))
  use #(blocks, pending, _state) <- result.try(parse_blueprints_blocks(
    state,
    pending,
  ))
  Ok(ast.BlueprintsFile(
    type_aliases:,
    extendables:,
    blocks:,
    trailing_comments: pending,
  ))
}

/// Parses an expects file from source text.
pub fn parse_expects_file(source: String) -> Result(ExpectsFile, ParserError) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(parser_error.TokenizerError),
  )
  let filtered = filter_whitespace(tokens)
  let state = init_state(filtered)
  let #(pending, state) = consume_comments(state)
  use #(extendables, pending, state) <- result.try(parse_extendables(
    state,
    pending,
  ))
  use #(blocks, pending, _state) <- result.try(parse_expects_blocks(
    state,
    pending,
  ))
  Ok(ast.ExpectsFile(extendables:, blocks:, trailing_comments: pending))
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
// BLUEPRINTS BLOCKS
// =============================================================================

/// Parse zero or more blueprints blocks.
fn parse_blueprints_blocks(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(BlueprintsBlock), List(Comment), ParserState), ParserError) {
  parse_blueprints_blocks_loop(state, [], pending)
}

fn parse_blueprints_blocks_loop(
  state: ParserState,
  acc: List(BlueprintsBlock),
  pending: List(Comment),
) -> Result(#(List(BlueprintsBlock), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.KeywordBlueprints -> {
      use #(block, state) <- result.try(parse_blueprints_block(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_blueprints_blocks_loop(state, [block, ..acc], next_pending)
    }
    token.EOF -> Ok(#(list.reverse(acc), pending, state))
    tok ->
      Error(parser_error.UnexpectedToken(
        "Blueprints",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_blueprints_block(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(BlueprintsBlock, ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordBlueprints, "Blueprints"))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(artifacts, state) <- result.try(parse_artifacts(state))
  use #(items, state) <- result.try(parse_blueprint_items(state))
  Ok(#(ast.BlueprintsBlock(artifacts:, items:, leading_comments:), state))
}

fn parse_artifacts(
  state: ParserState,
) -> Result(#(List(String), ParserState), ParserError) {
  case peek(state) {
    token.LiteralString(name) -> {
      let state = advance(state)
      parse_artifacts_loop(state, [name])
    }
    tok ->
      Error(parser_error.UnexpectedToken(
        "artifact name",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_artifacts_loop(
  state: ParserState,
  acc: List(String),
) -> Result(#(List(String), ParserState), ParserError) {
  case peek(state) {
    token.SymbolPlus -> {
      let state = advance(state)
      case peek(state) {
        token.LiteralString(name) -> {
          let state = advance(state)
          parse_artifacts_loop(state, [name, ..acc])
        }
        tok ->
          Error(parser_error.UnexpectedToken(
            "artifact name",
            token.to_string(tok),
            state.line,
            state.column,
          ))
      }
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_blueprint_items(
  state: ParserState,
) -> Result(#(List(BlueprintItem), ParserState), ParserError) {
  let #(pending, state) = consume_comments(state)
  parse_blueprint_items_loop(state, [], pending)
}

fn parse_blueprint_items_loop(
  state: ParserState,
  acc: List(BlueprintItem),
  pending: List(Comment),
) -> Result(#(List(BlueprintItem), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_blueprint_item(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_blueprint_items_loop(state, [item, ..acc], next_pending)
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_blueprint_item(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(BlueprintItem, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolStar, "*"))
  use #(name, state) <- result.try(parse_string_literal(state))
  use #(extends, state) <- result.try(parse_optional_extends(state))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  use state <- result.try(expect(state, token.KeywordRequires, "Requires"))
  use #(requires, state) <- result.try(parse_type_struct(state))
  use state <- result.try(expect(state, token.KeywordProvides, "Provides"))
  use #(provides, state) <- result.try(parse_literal_struct(state))
  Ok(#(
    ast.BlueprintItem(name:, extends:, requires:, provides:, leading_comments:),
    state,
  ))
}

// =============================================================================
// EXPECTS BLOCKS
// =============================================================================

/// Parse zero or more expects blocks.
fn parse_expects_blocks(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(ExpectsBlock), List(Comment), ParserState), ParserError) {
  parse_expects_blocks_loop(state, [], pending)
}

fn parse_expects_blocks_loop(
  state: ParserState,
  acc: List(ExpectsBlock),
  pending: List(Comment),
) -> Result(#(List(ExpectsBlock), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.KeywordExpectations -> {
      use #(block, state) <- result.try(parse_expects_block(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_expects_blocks_loop(state, [block, ..acc], next_pending)
    }
    token.EOF -> Ok(#(list.reverse(acc), pending, state))
    tok ->
      Error(parser_error.UnexpectedToken(
        "Expectations",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_expects_block(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(ExpectsBlock, ParserState), ParserError) {
  use state <- result.try(expect(
    state,
    token.KeywordExpectations,
    "Expectations",
  ))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(blueprint, state) <- result.try(parse_string_literal(state))
  use #(items, state) <- result.try(parse_expect_items(state))
  Ok(#(ast.ExpectsBlock(blueprint:, items:, leading_comments:), state))
}

fn parse_expect_items(
  state: ParserState,
) -> Result(#(List(ExpectItem), ParserState), ParserError) {
  let #(pending, state) = consume_comments(state)
  parse_expect_items_loop(state, [], pending)
}

fn parse_expect_items_loop(
  state: ParserState,
  acc: List(ExpectItem),
  pending: List(Comment),
) -> Result(#(List(ExpectItem), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_expect_item(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_expect_items_loop(state, [item, ..acc], next_pending)
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_expect_item(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(ExpectItem, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolStar, "*"))
  use #(name, state) <- result.try(parse_string_literal(state))
  use #(extends, state) <- result.try(parse_optional_extends(state))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  case peek(state) {
    token.KeywordRequires ->
      Error(parser_error.UnexpectedToken(
        "Provides",
        "Requires",
        state.line,
        state.column,
      ))
    _ -> {
      use state <- result.try(expect(state, token.KeywordProvides, "Provides"))
      use #(provides, state) <- result.try(parse_literal_struct(state))
      Ok(#(ast.ExpectItem(name:, extends:, provides:, leading_comments:), state))
    }
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
    token.Identifier(name) -> {
      let state = advance(state)
      parse_extends_list_loop(state, [name])
    }
    tok ->
      Error(parser_error.UnexpectedToken(
        "identifier",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_extends_list_loop(
  state: ParserState,
  acc: List(String),
) -> Result(#(List(String), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      case peek(state) {
        token.Identifier(name) -> {
          let state = advance(state)
          parse_extends_list_loop(state, [name, ..acc])
        }
        tok ->
          Error(parser_error.UnexpectedToken(
            "identifier",
            token.to_string(tok),
            state.line,
            state.column,
          ))
      }
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

// =============================================================================
// TYPE STRUCT (for Requires)
// =============================================================================

fn parse_type_struct(
  state: ParserState,
) -> Result(#(Struct, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  let #(pending, state) = consume_comments(state)
  use #(fields, trailing_comments, state) <- result.try(parse_type_fields(
    state,
    pending,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.Struct(fields:, trailing_comments:), state))
}

fn parse_type_fields(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBrace -> Ok(#([], pending, state))
    token.Identifier(_) -> {
      use #(field, state) <- result.try(parse_type_field(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_type_fields_loop(state, [field], next_pending)
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

fn parse_type_fields_loop(
  state: ParserState,
  acc: List(Field),
  pending: List(Comment),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      let #(next_pending, state) = consume_comments(state)
      // Allow trailing comma
      case peek(state) {
        token.SymbolRightBrace -> Ok(#(list.reverse(acc), next_pending, state))
        _ -> {
          use #(field, state) <- result.try(parse_type_field(
            state,
            next_pending,
          ))
          let #(next_pending, state) = consume_comments(state)
          parse_type_fields_loop(state, [field, ..acc], next_pending)
        }
      }
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
  }
}

fn parse_type_field(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(Field, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(type_, state) <- result.try(parse_type(state))
      Ok(#(
        ast.Field(name:, value: ast.TypeValue(type_), leading_comments:),
        state,
      ))
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
// LITERAL STRUCT (for Provides)
// =============================================================================

fn parse_literal_struct(
  state: ParserState,
) -> Result(#(Struct, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  let #(pending, state) = consume_comments(state)
  use #(fields, trailing_comments, state) <- result.try(parse_literal_fields(
    state,
    pending,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.Struct(fields:, trailing_comments:), state))
}

fn parse_literal_fields(
  state: ParserState,
  pending: List(Comment),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBrace -> Ok(#([], pending, state))
    token.Identifier(_) -> {
      use #(field, state) <- result.try(parse_literal_field(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_literal_fields_loop(state, [field], next_pending)
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

fn parse_literal_fields_loop(
  state: ParserState,
  acc: List(Field),
  pending: List(Comment),
) -> Result(#(List(Field), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      let #(next_pending, state) = consume_comments(state)
      // Allow trailing comma
      case peek(state) {
        token.SymbolRightBrace -> Ok(#(list.reverse(acc), next_pending, state))
        _ -> {
          use #(field, state) <- result.try(parse_literal_field(
            state,
            next_pending,
          ))
          let #(next_pending, state) = consume_comments(state)
          parse_literal_fields_loop(state, [field, ..acc], next_pending)
        }
      }
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
  }
}

fn parse_literal_field(
  state: ParserState,
  leading_comments: List(Comment),
) -> Result(#(Field, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(literal, state) <- result.try(parse_literal(state))
      Ok(#(
        ast.Field(name:, value: ast.LiteralValue(literal), leading_comments:),
        state,
      ))
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

fn parse_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString ->
      parse_type_with_refinement(state, primitive_types.String)
    token.KeywordInteger ->
      parse_type_with_refinement(
        state,
        primitive_types.NumericType(numeric_types.Integer),
      )
    token.KeywordFloat ->
      parse_type_with_refinement(
        state,
        primitive_types.NumericType(numeric_types.Float),
      )
    token.KeywordBoolean ->
      parse_type_with_refinement(state, primitive_types.Boolean)
    token.KeywordURL ->
      parse_type_with_refinement(
        state,
        primitive_types.SemanticType(semantic_types.URL),
      )
    token.KeywordList -> parse_list_type(state)
    token.KeywordDict -> parse_dict_type(state)
    token.KeywordOptional -> parse_optional_type(state)
    token.KeywordDefaulted -> parse_defaulted_type(state)
    // Type alias reference (must start with _, e.g., _env)
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(accepted_types.TypeAliasRef(name), state))
        }
        False -> Error(parser_error.UnknownType(name, state.line, state.column))
      }
    tok ->
      Error(parser_error.UnknownType(
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_type_with_refinement(
  state: ParserState,
  primitive: primitive_types.PrimitiveTypes,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  case peek(state) {
    token.SymbolLeftBrace -> {
      use #(refinement, state) <- result.try(parse_refinement(state, primitive))
      Ok(#(accepted_types.RefinementType(refinement), state))
    }
    _ -> Ok(#(accepted_types.PrimitiveType(primitive), state))
  }
}

/// Parses types valid inside collections: primitives, nested collections, or type alias refs.
/// Does not allow modifiers (Optional/Defaulted) or refinements directly.
fn parse_collection_inner_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString -> {
      let state = advance(state)
      Ok(#(accepted_types.PrimitiveType(primitive_types.String), state))
    }
    token.KeywordInteger -> {
      let state = advance(state)
      Ok(#(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Integer,
        )),
        state,
      ))
    }
    token.KeywordFloat -> {
      let state = advance(state)
      Ok(#(
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        state,
      ))
    }
    token.KeywordBoolean -> {
      let state = advance(state)
      Ok(#(accepted_types.PrimitiveType(primitive_types.Boolean), state))
    }
    token.KeywordURL -> {
      let state = advance(state)
      Ok(#(
        accepted_types.PrimitiveType(primitive_types.SemanticType(
          semantic_types.URL,
        )),
        state,
      ))
    }
    token.KeywordList -> parse_list_type(state)
    token.KeywordDict -> parse_dict_type(state)
    // Type alias reference (must start with _, e.g., _env)
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(accepted_types.TypeAliasRef(name), state))
        }
        False -> Error(parser_error.UnknownType(name, state.line, state.column))
      }
    tok ->
      Error(parser_error.UnknownType(
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_list_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(element, state) <- result.try(parse_collection_inner_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(accepted_types.CollectionType(collection_types.List(element)), state))
}

fn parse_dict_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  // Dict keys must be String primitive or type alias ref (for JSON compatibility)
  use #(key, state) <- result.try(parse_dict_key_type(state))
  use state <- result.try(expect(state, token.SymbolComma, ","))
  // Dict values can be primitives, nested collections, or type alias refs
  use #(value, state) <- result.try(parse_collection_inner_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(accepted_types.CollectionType(collection_types.Dict(key, value)), state))
}

/// Parses types valid as Dict keys: String primitive or type alias ref.
/// Only String is allowed as a primitive key (JSON keys must be strings).
fn parse_dict_key_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString -> {
      let state = advance(state)
      Ok(#(accepted_types.PrimitiveType(primitive_types.String), state))
    }
    // Type alias reference (must start with _, e.g., _env) - must resolve to a String-based type
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(accepted_types.TypeAliasRef(name), state))
        }
        False -> Error(parser_error.UnknownType(name, state.line, state.column))
      }
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
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(inner, state) <- result.try(parse_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(accepted_types.ModifierType(modifier_types.Optional(inner)), state))
}

fn parse_defaulted_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(inner, state) <- result.try(parse_type(state))
  use state <- result.try(expect(state, token.SymbolComma, ","))
  use #(default, state) <- result.try(parse_literal(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  let defaulted =
    accepted_types.ModifierType(modifier_types.Defaulted(
      inner,
      literal_to_string(default),
    ))
  // Check for optional refinement: Defaulted(String, "x") { x | x in { ... } }
  case peek(state) {
    token.SymbolLeftBrace -> {
      use #(refinement, state) <- result.try(parse_defaulted_refinement(
        state,
        defaulted,
      ))
      Ok(#(accepted_types.RefinementType(refinement), state))
    }
    _ -> Ok(#(defaulted, state))
  }
}

/// Parse refinement on a Defaulted type: { x | x in { ... } } or { x | x in ( ... ) }
fn parse_defaulted_refinement(
  state: ParserState,
  defaulted: AcceptedTypes,
) -> Result(
  #(refinement_types.RefinementTypes(AcceptedTypes), ParserState),
  ParserError,
) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.SymbolPipe, "|"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.KeywordIn, "in"))
  use #(refinement, state) <- result.try(parse_defaulted_refinement_body(
    state,
    defaulted,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(refinement, state))
}

fn parse_defaulted_refinement_body(
  state: ParserState,
  defaulted: AcceptedTypes,
) -> Result(
  #(refinement_types.RefinementTypes(AcceptedTypes), ParserState),
  ParserError,
) {
  let primitive = extract_primitive_from_accepted(defaulted)
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
      use _ <- result.try(case primitive {
        Ok(prim) -> validate_oneof_literals(values, prim, state)
        Error(_) -> Ok(Nil)
      })
      let string_values = list.map(values, literal_to_string)
      Ok(#(
        refinement_types.OneOf(defaulted, set.from_list(string_values)),
        state,
      ))
    }
    // Range: ( min..max )
    token.SymbolLeftParen -> {
      let state = advance(state)
      use #(min, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolDotDot, ".."))
      use #(max, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolRightParen, ")"))
      use _ <- result.try(case primitive {
        Ok(prim) -> validate_oneof_literals([min, max], prim, state)
        Error(_) -> Ok(Nil)
      })
      Ok(#(
        refinement_types.InclusiveRange(
          defaulted,
          literal_to_string(min),
          literal_to_string(max),
        ),
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
// REFINEMENTS
// =============================================================================

fn parse_refinement(
  state: ParserState,
  primitive: primitive_types.PrimitiveTypes,
) -> Result(
  #(refinement_types.RefinementTypes(AcceptedTypes), ParserState),
  ParserError,
) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.SymbolPipe, "|"))
  use state <- result.try(expect_x(state))
  use state <- result.try(expect(state, token.KeywordIn, "in"))
  use #(refinement, state) <- result.try(parse_refinement_body(state, primitive))
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
  primitive: primitive_types.PrimitiveTypes,
) -> Result(
  #(refinement_types.RefinementTypes(AcceptedTypes), ParserState),
  ParserError,
) {
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
      use _ <- result.try(validate_oneof_literals(values, primitive, state))
      let string_values = list.map(values, literal_to_string)
      Ok(#(
        refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive),
          set.from_list(string_values),
        ),
        state,
      ))
    }
    // Range: ( min..max )
    token.SymbolLeftParen -> {
      let state = advance(state)
      use #(min, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolDotDot, ".."))
      use #(max, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolRightParen, ")"))
      use _ <- result.try(validate_oneof_literals([min, max], primitive, state))
      Ok(#(
        refinement_types.InclusiveRange(
          accepted_types.PrimitiveType(primitive),
          literal_to_string(min),
          literal_to_string(max),
        ),
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
    token.LiteralTrue -> Ok(#(ast.LiteralTrue, advance(state)))
    token.LiteralFalse -> Ok(#(ast.LiteralFalse, advance(state)))
    token.SymbolLeftBracket -> parse_literal_list(state)
    token.SymbolLeftBrace -> parse_literal_struct_value(state)
    tok ->
      Error(parser_error.UnexpectedToken(
        "literal value",
        token.to_string(tok),
        state.line,
        state.column,
      ))
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
      parse_literal_list_loop(state, [first])
    }
  }
}

fn parse_literal_list_loop(
  state: ParserState,
  acc: List(Literal),
) -> Result(#(List(Literal), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      use #(literal, state) <- result.try(parse_literal(state))
      parse_literal_list_loop(state, [literal, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_literal_struct_value(
  state: ParserState,
) -> Result(#(Literal, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolLeftBrace, "{"))
  let #(pending, state) = consume_comments(state)
  use #(fields, _trailing_comments, state) <- result.try(parse_literal_fields(
    state,
    pending,
  ))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.LiteralStruct(fields), state))
}

/// Convert a Literal to its string representation for use in refinements/defaults.
fn literal_to_string(literal: Literal) -> String {
  case literal {
    ast.LiteralString(s) -> s
    ast.LiteralInteger(n) -> int.to_string(n)
    ast.LiteralFloat(f) -> float.to_string(f)
    ast.LiteralTrue -> "True"
    ast.LiteralFalse -> "False"
    ast.LiteralList(_) -> "[]"
    ast.LiteralStruct(_) -> "{}"
  }
}

/// Validates that all literals in a OneOf set match the declared primitive type.
fn validate_oneof_literals(
  literals: List(Literal),
  primitive: primitive_types.PrimitiveTypes,
  state: ParserState,
) -> Result(Nil, ParserError) {
  case literals {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      case literal_matches_primitive(first, primitive) {
        True -> validate_oneof_literals(rest, primitive, state)
        False ->
          Error(parser_error.InvalidRefinement(
            "value '"
              <> literal_to_string(first)
              <> "' is not a valid "
              <> primitive_types.primitive_type_to_string(primitive)
              <> " literal",
            state.line,
            state.column,
          ))
      }
    }
  }
}

/// Checks if a literal value is compatible with the declared primitive type.
fn literal_matches_primitive(
  literal: Literal,
  primitive: primitive_types.PrimitiveTypes,
) -> Bool {
  case primitive, literal {
    primitive_types.String, ast.LiteralString(_) -> True
    primitive_types.NumericType(numeric_types.Integer), ast.LiteralInteger(_) ->
      True
    primitive_types.NumericType(numeric_types.Float), ast.LiteralFloat(_) ->
      True
    primitive_types.Boolean, ast.LiteralTrue -> True
    primitive_types.Boolean, ast.LiteralFalse -> True
    primitive_types.SemanticType(_), ast.LiteralString(_) -> True
    _, _ -> False
  }
}

/// Extracts the primitive type from an AcceptedTypes, unwrapping Defaulted modifiers.
fn extract_primitive_from_accepted(
  typ: AcceptedTypes,
) -> Result(primitive_types.PrimitiveTypes, Nil) {
  case typ {
    accepted_types.PrimitiveType(primitive) -> Ok(primitive)
    accepted_types.ModifierType(modifier_types.Defaulted(inner, _)) ->
      extract_primitive_from_accepted(inner)
    _ -> Error(Nil)
  }
}
