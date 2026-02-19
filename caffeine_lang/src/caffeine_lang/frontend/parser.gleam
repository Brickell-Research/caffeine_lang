import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsBlock, type BlueprintsFile, type Comment,
  type ExpectItem, type ExpectsBlock, type ExpectsFile, type Extendable,
  type ExtendableKind, type Field, type Literal, type ParsedArtifactRef,
  type Struct, type TypeAlias,
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
      use #(block, trailing, state) <- result.try(parse_blueprints_block(
        state,
        pending,
      ))
      let #(more_comments, state) = consume_comments(state)
      let next_pending = list.append(trailing, more_comments)
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
) -> Result(#(BlueprintsBlock, List(Comment), ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordBlueprints, "Blueprints"))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(artifacts, state) <- result.try(parse_artifacts(state))
  use #(items, trailing, state) <- result.try(parse_blueprint_items(state))
  Ok(#(
    ast.BlueprintsBlock(artifacts:, items:, leading_comments:),
    trailing,
    state,
  ))
}

fn parse_artifacts(
  state: ParserState,
) -> Result(#(List(ParsedArtifactRef), ParserState), ParserError) {
  case peek(state) {
    token.LiteralString(name) -> {
      use ref <- result.try(resolve_artifact_ref(name, state))
      let state = advance(state)
      parse_artifacts_loop(state, [ref])
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
  acc: List(ParsedArtifactRef),
) -> Result(#(List(ParsedArtifactRef), ParserState), ParserError) {
  case peek(state) {
    token.SymbolPlus -> {
      let state = advance(state)
      case peek(state) {
        token.LiteralString(name) -> {
          use ref <- result.try(resolve_artifact_ref(name, state))
          let state = advance(state)
          parse_artifacts_loop(state, [ref, ..acc])
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

/// Resolves an artifact name string to a ParsedArtifactRef.
fn resolve_artifact_ref(
  name: String,
  state: ParserState,
) -> Result(ParsedArtifactRef, ParserError) {
  case name {
    "SLO" -> Ok(ast.ParsedSLO)
    "DependencyRelations" -> Ok(ast.ParsedDependencyRelations)
    _ ->
      Error(parser_error.UnexpectedToken(
        "\"SLO\" or \"DependencyRelations\"",
        "\"" <> name <> "\"",
        state.line,
        state.column,
      ))
  }
}

fn parse_blueprint_items(
  state: ParserState,
) -> Result(#(List(BlueprintItem), List(Comment), ParserState), ParserError) {
  let #(pending, state) = consume_comments(state)
  parse_blueprint_items_loop(state, [], pending)
}

fn parse_blueprint_items_loop(
  state: ParserState,
  acc: List(BlueprintItem),
  pending: List(Comment),
) -> Result(#(List(BlueprintItem), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_blueprint_item(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_blueprint_items_loop(state, [item, ..acc], next_pending)
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
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
      use #(block, trailing, state) <- result.try(parse_expects_block(
        state,
        pending,
      ))
      let #(more_comments, state) = consume_comments(state)
      let next_pending = list.append(trailing, more_comments)
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
) -> Result(#(ExpectsBlock, List(Comment), ParserState), ParserError) {
  use state <- result.try(expect(
    state,
    token.KeywordExpectations,
    "Expectations",
  ))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(blueprint, state) <- result.try(parse_string_literal(state))
  use #(items, trailing, state) <- result.try(parse_expect_items(state))
  Ok(#(ast.ExpectsBlock(blueprint:, items:, leading_comments:), trailing, state))
}

fn parse_expect_items(
  state: ParserState,
) -> Result(#(List(ExpectItem), List(Comment), ParserState), ParserError) {
  let #(pending, state) = consume_comments(state)
  parse_expect_items_loop(state, [], pending)
}

fn parse_expect_items_loop(
  state: ParserState,
  acc: List(ExpectItem),
  pending: List(Comment),
) -> Result(#(List(ExpectItem), List(Comment), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_expect_item(state, pending))
      let #(next_pending, state) = consume_comments(state)
      parse_expect_items_loop(state, [item, ..acc], next_pending)
    }
    _ -> Ok(#(list.reverse(acc), pending, state))
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

fn parse_type(
  state: ParserState,
) -> Result(#(ParsedType, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString -> parse_type_with_refinement(state, StringType)
    token.KeywordInteger ->
      parse_type_with_refinement(state, NumericType(Integer))
    token.KeywordFloat -> parse_type_with_refinement(state, NumericType(Float))
    token.KeywordBoolean -> parse_type_with_refinement(state, Boolean)
    token.KeywordURL -> parse_type_with_refinement(state, SemanticType(URL))
    token.KeywordPercentage ->
      parse_type_with_refinement(state, NumericType(Percentage))
    token.KeywordList -> parse_list_type(state)
    token.KeywordDict -> parse_dict_type(state)
    token.KeywordOptional -> parse_optional_type(state)
    token.KeywordDefaulted -> parse_defaulted_type(state)
    // Record type (e.g., { numerator: String, denominator: String })
    token.SymbolLeftBrace -> parse_record_type(state)
    // Type alias reference (must start with _, e.g., _env)
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(ParsedTypeAliasRef(name), state))
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
  primitive: PrimitiveTypes,
) -> Result(#(ParsedType, ParserState), ParserError) {
  let state = advance(state)
  case peek(state) {
    token.SymbolLeftBrace -> {
      use #(refinement, state) <- result.try(parse_refinement(state, primitive))
      Ok(#(ParsedRefinement(refinement), state))
    }
    _ -> Ok(#(ParsedPrimitive(primitive), state))
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
  case peek(state) {
    token.KeywordString -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(StringType), state))
    }
    token.KeywordInteger -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(NumericType(Integer)), state))
    }
    token.KeywordFloat -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(NumericType(Float)), state))
    }
    token.KeywordBoolean -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(Boolean), state))
    }
    token.KeywordURL -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(SemanticType(URL)), state))
    }
    token.KeywordPercentage -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(NumericType(Percentage)), state))
    }
    token.KeywordList -> parse_list_type(state)
    token.KeywordDict -> parse_dict_type(state)
    // Record type (e.g., { numerator: String, denominator: String })
    token.SymbolLeftBrace -> parse_record_type(state)
    // Type alias reference (must start with _, e.g., _env)
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(ParsedTypeAliasRef(name), state))
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
    token.KeywordString -> {
      let state = advance(state)
      Ok(#(ParsedPrimitive(StringType), state))
    }
    // Type alias reference (must start with _, e.g., _env) - must resolve to a String-based type
    token.Identifier(name) ->
      case string.starts_with(name, "_") {
        True -> {
          let state = advance(state)
          Ok(#(ParsedTypeAliasRef(name), state))
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
      use #(refinement, state) <- result.try(parse_defaulted_refinement(
        state,
        defaulted,
      ))
      Ok(#(ParsedRefinement(refinement), state))
    }
    _ -> Ok(#(defaulted, state))
  }
}

/// Parse refinement on a Defaulted type: { x | x in { ... } } or { x | x in ( ... ) }
fn parse_defaulted_refinement(
  state: ParserState,
  defaulted: ParsedType,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
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
  defaulted: ParsedType,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
      let string_values = list.map(values, literal_to_string)
      Ok(#(OneOf(defaulted, set.from_list(string_values)), state))
    }
    // Range: ( min..max )
    token.SymbolLeftParen -> {
      let state = advance(state)
      use #(min, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolDotDot, ".."))
      use #(max, state) <- result.try(parse_literal(state))
      use state <- result.try(expect(state, token.SymbolRightParen, ")"))
      Ok(#(
        InclusiveRange(
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
  primitive: PrimitiveTypes,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
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
  primitive: PrimitiveTypes,
) -> Result(#(RefinementTypes(ParsedType), ParserState), ParserError) {
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
      let string_values = list.map(values, literal_to_string)
      Ok(#(
        OneOf(ParsedPrimitive(primitive), set.from_list(string_values)),
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
      Ok(#(
        InclusiveRange(
          ParsedPrimitive(primitive),
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
    token.LiteralPercentage(f) ->
      Ok(#(ast.LiteralPercentage(f), advance(state)))
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
fn literal_to_string(literal: Literal) -> String {
  case literal {
    ast.LiteralString(s) -> s
    ast.LiteralInteger(n) -> int.to_string(n)
    ast.LiteralFloat(f) -> float.to_string(f)
    ast.LiteralPercentage(f) -> float.to_string(f) <> "%"
    ast.LiteralTrue -> "True"
    ast.LiteralFalse -> "False"
    ast.LiteralList(_) -> "[]"
    ast.LiteralStruct(_, _) -> "{}"
  }
}
