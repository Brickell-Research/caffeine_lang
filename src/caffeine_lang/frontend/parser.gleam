import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsBlock, type BlueprintsFile, type ExpectItem,
  type ExpectsBlock, type ExpectsFile, type Extendable, type ExtendableKind,
  type Field, type Literal, type Struct,
}
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/token.{type Token}
import caffeine_lang/frontend/tokenizer
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set

/// Parser state tracking position in token stream.
type ParserState {
  ParserState(tokens: List(Token), line: Int, column: Int)
}

/// Parses a blueprints file from source text.
pub fn parse_blueprints_file(
  source: String,
) -> Result(BlueprintsFile, ParserError) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(parser_error.TokenizerError),
  )
  let state =
    ParserState(tokens: filter_whitespace_comments(tokens), line: 1, column: 1)
  use #(extendables, state) <- result.try(parse_extendables(state))
  use #(blocks, _state) <- result.try(parse_blueprints_blocks(state))
  Ok(ast.BlueprintsFile(extendables:, blocks:))
}

/// Parses an expects file from source text.
pub fn parse_expects_file(source: String) -> Result(ExpectsFile, ParserError) {
  use tokens <- result.try(
    tokenizer.tokenize(source)
    |> result.map_error(parser_error.TokenizerError),
  )
  let state =
    ParserState(tokens: filter_whitespace_comments(tokens), line: 1, column: 1)
  use #(extendables, state) <- result.try(parse_extendables(state))
  use #(blocks, _state) <- result.try(parse_expects_blocks(state))
  Ok(ast.ExpectsFile(extendables:, blocks:))
}

/// Filter out whitespace and comment tokens.
fn filter_whitespace_comments(tokens: List(Token)) -> List(Token) {
  list.filter(tokens, fn(tok) {
    case tok {
      token.WhitespaceNewline
      | token.WhitespaceIndent(_)
      | token.CommentLine(_)
      | token.CommentSection(_) -> False
      _ -> True
    }
  })
}

/// Peek at the current token without consuming it.
fn peek(state: ParserState) -> Token {
  case state.tokens {
    [tok, ..] -> tok
    [] -> token.EOF
  }
}

/// Consume current token and advance state.
fn advance(state: ParserState) -> ParserState {
  case state.tokens {
    [_, ..rest] -> ParserState(..state, tokens: rest)
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
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// EXTENDABLES
// =============================================================================

/// Parse zero or more extendables at file start.
fn parse_extendables(
  state: ParserState,
) -> Result(#(List(Extendable), ParserState), ParserError) {
  parse_extendables_loop(state, [])
}

fn parse_extendables_loop(
  state: ParserState,
  acc: List(Extendable),
) -> Result(#(List(Extendable), ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      use #(extendable, state) <- result.try(parse_extendable(state, name))
      parse_extendables_loop(state, [extendable, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_extendable(
  state: ParserState,
  name: String,
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
  Ok(#(ast.Extendable(name:, kind:, body:), state))
}

fn parse_extendable_kind(
  state: ParserState,
) -> Result(#(ExtendableKind, ParserState), ParserError) {
  case peek(state) {
    token.KeywordRequires -> Ok(#(ast.ExtendableRequires, advance(state)))
    token.KeywordProvides -> Ok(#(ast.ExtendableProvides, advance(state)))
    tok ->
      Error(parser_error.UnexpectedToken(
        "Requires or Provides",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

// =============================================================================
// BLUEPRINTS BLOCKS
// =============================================================================

/// Parse one or more blueprints blocks.
fn parse_blueprints_blocks(
  state: ParserState,
) -> Result(#(List(BlueprintsBlock), ParserState), ParserError) {
  case peek(state) {
    token.EOF -> Error(parser_error.EmptyFile(state.line, state.column))
    _ -> parse_blueprints_blocks_loop(state, [])
  }
}

fn parse_blueprints_blocks_loop(
  state: ParserState,
  acc: List(BlueprintsBlock),
) -> Result(#(List(BlueprintsBlock), ParserState), ParserError) {
  case peek(state) {
    token.KeywordBlueprints -> {
      use #(block, state) <- result.try(parse_blueprints_block(state))
      parse_blueprints_blocks_loop(state, [block, ..acc])
    }
    token.EOF -> Ok(#(list.reverse(acc), state))
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
) -> Result(#(BlueprintsBlock, ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordBlueprints, "Blueprints"))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(artifacts, state) <- result.try(parse_artifacts(state))
  use #(items, state) <- result.try(parse_blueprint_items(state))
  Ok(#(ast.BlueprintsBlock(artifacts:, items:), state))
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
  parse_blueprint_items_loop(state, [])
}

fn parse_blueprint_items_loop(
  state: ParserState,
  acc: List(BlueprintItem),
) -> Result(#(List(BlueprintItem), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_blueprint_item(state))
      parse_blueprint_items_loop(state, [item, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_blueprint_item(
  state: ParserState,
) -> Result(#(BlueprintItem, ParserState), ParserError) {
  use state <- result.try(expect(state, token.SymbolStar, "*"))
  use #(name, state) <- result.try(parse_string_literal(state))
  use #(extends, state) <- result.try(parse_optional_extends(state))
  use state <- result.try(expect(state, token.SymbolColon, ":"))
  use state <- result.try(expect(state, token.KeywordRequires, "Requires"))
  use #(requires, state) <- result.try(parse_type_struct(state))
  use state <- result.try(expect(state, token.KeywordProvides, "Provides"))
  use #(provides, state) <- result.try(parse_literal_struct(state))
  Ok(#(ast.BlueprintItem(name:, extends:, requires:, provides:), state))
}

// =============================================================================
// EXPECTS BLOCKS
// =============================================================================

/// Parse one or more expects blocks.
fn parse_expects_blocks(
  state: ParserState,
) -> Result(#(List(ExpectsBlock), ParserState), ParserError) {
  case peek(state) {
    token.EOF -> Error(parser_error.EmptyFile(state.line, state.column))
    _ -> parse_expects_blocks_loop(state, [])
  }
}

fn parse_expects_blocks_loop(
  state: ParserState,
  acc: List(ExpectsBlock),
) -> Result(#(List(ExpectsBlock), ParserState), ParserError) {
  case peek(state) {
    token.KeywordExpects -> {
      use #(block, state) <- result.try(parse_expects_block(state))
      parse_expects_blocks_loop(state, [block, ..acc])
    }
    token.EOF -> Ok(#(list.reverse(acc), state))
    tok ->
      Error(parser_error.UnexpectedToken(
        "Expects",
        token.to_string(tok),
        state.line,
        state.column,
      ))
  }
}

fn parse_expects_block(
  state: ParserState,
) -> Result(#(ExpectsBlock, ParserState), ParserError) {
  use state <- result.try(expect(state, token.KeywordExpects, "Expects"))
  use state <- result.try(expect(state, token.KeywordFor, "for"))
  use #(blueprint, state) <- result.try(parse_string_literal(state))
  use #(items, state) <- result.try(parse_expect_items(state))
  Ok(#(ast.ExpectsBlock(blueprint:, items:), state))
}

fn parse_expect_items(
  state: ParserState,
) -> Result(#(List(ExpectItem), ParserState), ParserError) {
  parse_expect_items_loop(state, [])
}

fn parse_expect_items_loop(
  state: ParserState,
  acc: List(ExpectItem),
) -> Result(#(List(ExpectItem), ParserState), ParserError) {
  case peek(state) {
    token.SymbolStar -> {
      use #(item, state) <- result.try(parse_expect_item(state))
      parse_expect_items_loop(state, [item, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_expect_item(
  state: ParserState,
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
      Ok(#(ast.ExpectItem(name:, extends:, provides:), state))
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
  use #(fields, state) <- result.try(parse_type_fields(state))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.Struct(fields:), state))
}

fn parse_type_fields(
  state: ParserState,
) -> Result(#(List(Field), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBrace -> Ok(#([], state))
    token.Identifier(_) -> {
      use #(field, state) <- result.try(parse_type_field(state))
      parse_type_fields_loop(state, [field])
    }
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
) -> Result(#(List(Field), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      use #(field, state) <- result.try(parse_type_field(state))
      parse_type_fields_loop(state, [field, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_type_field(
  state: ParserState,
) -> Result(#(Field, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(type_, state) <- result.try(parse_type(state))
      Ok(#(ast.Field(name:, value: ast.TypeValue(type_)), state))
    }
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
  use #(fields, state) <- result.try(parse_literal_fields(state))
  use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
  Ok(#(ast.Struct(fields:), state))
}

fn parse_literal_fields(
  state: ParserState,
) -> Result(#(List(Field), ParserState), ParserError) {
  case peek(state) {
    token.SymbolRightBrace -> Ok(#([], state))
    token.Identifier(_) -> {
      use #(field, state) <- result.try(parse_literal_field(state))
      parse_literal_fields_loop(state, [field])
    }
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
) -> Result(#(List(Field), ParserState), ParserError) {
  case peek(state) {
    token.SymbolComma -> {
      let state = advance(state)
      use #(field, state) <- result.try(parse_literal_field(state))
      parse_literal_fields_loop(state, [field, ..acc])
    }
    _ -> Ok(#(list.reverse(acc), state))
  }
}

fn parse_literal_field(
  state: ParserState,
) -> Result(#(Field, ParserState), ParserError) {
  case peek(state) {
    token.Identifier(name) -> {
      let state = advance(state)
      use state <- result.try(expect(state, token.SymbolColon, ":"))
      use #(literal, state) <- result.try(parse_literal(state))
      Ok(#(ast.Field(name:, value: ast.LiteralValue(literal)), state))
    }
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
    token.KeywordList -> parse_list_type(state)
    token.KeywordDict -> parse_dict_type(state)
    token.KeywordOptional -> parse_optional_type(state)
    token.KeywordDefaulted -> parse_defaulted_type(state)
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

fn parse_list_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(element, state) <- result.try(parse_primitive_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(
    accepted_types.CollectionType(
      collection_types.List(accepted_types.PrimitiveType(element)),
    ),
    state,
  ))
}

fn parse_dict_type(
  state: ParserState,
) -> Result(#(AcceptedTypes, ParserState), ParserError) {
  let state = advance(state)
  use state <- result.try(expect(state, token.SymbolLeftParen, "("))
  use #(key, state) <- result.try(parse_primitive_type(state))
  use state <- result.try(expect(state, token.SymbolComma, ","))
  use #(value, state) <- result.try(parse_primitive_type(state))
  use state <- result.try(expect(state, token.SymbolRightParen, ")"))
  Ok(#(
    accepted_types.CollectionType(collection_types.Dict(
      accepted_types.PrimitiveType(key),
      accepted_types.PrimitiveType(value),
    )),
    state,
  ))
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
  case peek(state) {
    // OneOf: { value1, value2, ... }
    token.SymbolLeftBrace -> {
      let state = advance(state)
      use #(values, state) <- result.try(parse_literal_list_contents(state))
      use state <- result.try(expect(state, token.SymbolRightBrace, "}"))
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

fn parse_primitive_type(
  state: ParserState,
) -> Result(#(primitive_types.PrimitiveTypes, ParserState), ParserError) {
  case peek(state) {
    token.KeywordString -> Ok(#(primitive_types.String, advance(state)))
    token.KeywordInteger ->
      Ok(#(primitive_types.NumericType(numeric_types.Integer), advance(state)))
    token.KeywordFloat ->
      Ok(#(primitive_types.NumericType(numeric_types.Float), advance(state)))
    token.KeywordBoolean -> Ok(#(primitive_types.Boolean, advance(state)))
    tok ->
      Error(parser_error.UnknownType(
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
  use #(fields, state) <- result.try(parse_literal_fields(state))
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
