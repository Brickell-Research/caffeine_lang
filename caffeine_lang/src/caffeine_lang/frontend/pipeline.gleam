/// Frontend pipeline for compiling .caffeine source files.
/// Orchestrates the tokenizer, parser, validator, and generator
/// to transform .caffeine source into Blueprint and Expectation types.
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/lowering
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error.{type ParserError}
import caffeine_lang/frontend/tokenizer_error
import caffeine_lang/frontend/validator
import caffeine_lang/linker/blueprints.{type Blueprint}
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/position_utils
import caffeine_lang/rich_error.{
  type RichError, ErrorCode, RichError, SourceLocation,
}
import caffeine_lang/source_file.{type SourceFile}
import caffeine_lang/string_distance
import gleam/list
import gleam/option
import gleam/result
import gleam/string

/// Compiles a blueprints .caffeine source to a list of blueprints.
@internal
pub fn compile_blueprints(
  source: SourceFile,
) -> Result(List(Blueprint), CompilationError) {
  use ast <- result.try(
    parser.parse_blueprints_file(source.content)
    |> result.map_error(fn(err) {
      parser_error_to_compilation_error(err, source.path)
    }),
  )
  use validated <- result.try(
    validator.validate_blueprints_file(ast)
    |> result.map_error(fn(errs) {
      validator_errors_to_compilation_error(errs, source.path)
    }),
  )
  lowering.lower_blueprints(validated)
}

/// Compiles an expects .caffeine source to a list of expectations.
@internal
pub fn compile_expects(
  source: SourceFile,
) -> Result(List(Expectation), CompilationError) {
  use ast <- result.try(
    parser.parse_expects_file(source.content)
    |> result.map_error(fn(err) {
      parser_error_to_compilation_error(err, source.path)
    }),
  )
  use validated <- result.try(
    validator.validate_expects_file(ast)
    |> result.map_error(fn(errs) {
      validator_errors_to_compilation_error(errs, source.path)
    }),
  )
  Ok(lowering.lower_expectations(validated))
}

fn parser_error_to_compilation_error(
  err: parser_error.ParserError,
  file_path: String,
) -> CompilationError {
  errors.FrontendParseError(file_path <> ": " <> parser_error.to_string(err))
}

fn validator_error_to_compilation_error(
  err: validator.ValidatorError,
  file_path: String,
) -> CompilationError {
  errors.FrontendValidationError(
    file_path <> ": " <> validator_error_to_string(err),
  )
}

/// Converts a list of ValidatorErrors to a single CompilationError.
fn validator_errors_to_compilation_error(
  errs: List(validator.ValidatorError),
  file_path: String,
) -> CompilationError {
  case errs {
    [single] -> validator_error_to_compilation_error(single, file_path)
    multiple -> {
      let compilation_errors =
        multiple
        |> list.map(validator_error_to_compilation_error(_, file_path))
      errors.CompilationErrors(errors: compilation_errors)
    }
  }
}

fn validator_error_to_string(err: validator.ValidatorError) -> String {
  case err {
    validator.DuplicateExtendable(name) -> "Duplicate extendable: " <> name
    validator.UndefinedExtendable(name, referenced_by, _candidates) ->
      "Undefined extendable '"
      <> name
      <> "' referenced by '"
      <> referenced_by
      <> "'"
    validator.DuplicateExtendsReference(name, referenced_by) ->
      "Duplicate extends reference '"
      <> name
      <> "' in '"
      <> referenced_by
      <> "'"
    validator.InvalidExtendableKind(name, expected, got) ->
      "Invalid extendable kind for '"
      <> name
      <> "': expected "
      <> expected
      <> ", got "
      <> got
    validator.UndefinedTypeAlias(name, referenced_by, _candidates) ->
      "Undefined type alias '"
      <> name
      <> "' referenced by '"
      <> referenced_by
      <> "'"
    validator.DuplicateTypeAlias(name) -> "Duplicate type alias: " <> name
    validator.CircularTypeAlias(name, _cycle) ->
      "Circular type alias reference detected in '" <> name <> "'"
    validator.InvalidDictKeyTypeAlias(alias_name, resolved_to, referenced_by) ->
      "Type alias '"
      <> alias_name
      <> "' used as Dict key resolves to '"
      <> resolved_to
      <> "' which is not String-based, in '"
      <> referenced_by
      <> "'"
    validator.ExtendableOvershadowing(field_name, item_name, extendable_name) ->
      "Field '"
      <> field_name
      <> "' in '"
      <> item_name
      <> "' overshadows field from extendable '"
      <> extendable_name
      <> "'"
    validator.ExtendableTypeAliasNameCollision(name) ->
      "Name '" <> name <> "' is used as both an extendable and a type alias"
  }
}

// =============================================================================
// RICH ERROR PIPELINE
// =============================================================================

/// Compiles blueprints with rich error information including source locations.
@internal
pub fn compile_blueprints_rich(
  source: SourceFile,
) -> Result(List(Blueprint), RichError) {
  use ast <- result.try(
    parser.parse_blueprints_file(source.content)
    |> result.map_error(fn(err) { parser_error_to_rich_error(err, source) }),
  )
  use validated <- result.try(
    validator.validate_blueprints_file(ast)
    |> result.map_error(fn(errs) {
      validator_errors_to_rich_error(errs, source)
    }),
  )
  lowering.lower_blueprints(validated)
  |> result.map_error(fn(err) { rich_error.from_compilation_error(err) })
}

/// Compiles expects with rich error information including source locations.
@internal
pub fn compile_expects_rich(
  source: SourceFile,
) -> Result(List(Expectation), RichError) {
  use ast <- result.try(
    parser.parse_expects_file(source.content)
    |> result.map_error(fn(err) { parser_error_to_rich_error(err, source) }),
  )
  use validated <- result.try(
    validator.validate_expects_file(ast)
    |> result.map_error(fn(errs) {
      validator_errors_to_rich_error(errs, source)
    }),
  )
  Ok(lowering.lower_expectations(validated))
}

/// Converts a ParserError to a RichError with location info.
fn parser_error_to_rich_error(err: ParserError, source: SourceFile) -> RichError {
  let compilation_error = parser_error_to_compilation_error(err, source.path)
  let #(location, suggestion) = case err {
    parser_error.TokenizerError(tok_err) -> {
      let #(line, column) = case tok_err {
        tokenizer_error.UnterminatedString(line, column) -> #(line, column)
        tokenizer_error.InvalidCharacter(line, column, _) -> #(line, column)
      }
      #(
        option.Some(SourceLocation(line:, column:, end_column: option.None)),
        option.None,
      )
    }
    parser_error.UnexpectedToken(_, got, line, column) -> #(
      option.Some(SourceLocation(
        line:,
        column:,
        end_column: option.Some(column + string.length(got)),
      )),
      option.None,
    )
    parser_error.UnexpectedEOF(_, line, column) -> #(
      option.Some(SourceLocation(line:, column:, end_column: option.None)),
      option.None,
    )
    parser_error.UnknownType(name, line, column) -> {
      let known_types = [
        "String", "Integer", "Float", "Boolean", "URL", "List", "Dict",
        "Optional", "Defaulted",
      ]
      #(
        option.Some(SourceLocation(
          line:,
          column:,
          end_column: option.Some(column + string.length(name)),
        )),
        string_distance.closest_match(name, known_types),
      )
    }
    parser_error.InvalidRefinement(_, line, column) -> #(
      option.Some(SourceLocation(line:, column:, end_column: option.None)),
      option.None,
    )
    parser_error.QuotedFieldName(_, line, column) -> #(
      option.Some(SourceLocation(line:, column:, end_column: option.None)),
      option.None,
    )
    parser_error.InvalidTypeAliasName(name, _, line, column) -> #(
      option.Some(SourceLocation(
        line:,
        column:,
        end_column: option.Some(column + string.length(name)),
      )),
      option.None,
    )
  }
  RichError(
    error: compilation_error,
    code: rich_error.error_code_for(compilation_error),
    source_path: option.Some(source.path),
    source_content: option.Some(source.content),
    location:,
    suggestion:,
  )
}

/// Converts a list of ValidatorErrors to a RichError.
/// Uses the first error for the primary rich error since RichError is a single error.
fn validator_errors_to_rich_error(
  errs: List(validator.ValidatorError),
  source: SourceFile,
) -> RichError {
  case errs {
    // Single error gets full rich error treatment
    [single] -> validator_error_to_rich_error(single, source)
    // Multiple errors: use the first for location, combine messages
    [first, ..] -> {
      let compilation_error =
        validator_errors_to_compilation_error(errs, source.path)
      let first_rich = validator_error_to_rich_error(first, source)
      RichError(
        error: compilation_error,
        code: first_rich.code,
        source_path: first_rich.source_path,
        source_content: first_rich.source_content,
        location: first_rich.location,
        suggestion: first_rich.suggestion,
      )
    }
    // Empty list should not happen, but handle gracefully
    [] ->
      rich_error.from_compilation_error(errors.FrontendValidationError(
        source.path <> ": unknown validation error",
      ))
  }
}

/// Converts a ValidatorError to a RichError with location info.
fn validator_error_to_rich_error(
  err: validator.ValidatorError,
  source: SourceFile,
) -> RichError {
  let compilation_error = validator_error_to_compilation_error(err, source.path)
  let #(name, suggestion) = case err {
    validator.UndefinedExtendable(name, _, candidates) -> #(
      name,
      string_distance.closest_match(name, candidates),
    )
    validator.UndefinedTypeAlias(name, _, candidates) -> #(
      name,
      string_distance.closest_match(name, candidates),
    )
    validator.DuplicateExtendable(name) -> #(name, option.None)
    validator.DuplicateExtendsReference(name, _) -> #(name, option.None)
    validator.InvalidExtendableKind(name, _, _) -> #(name, option.None)
    validator.DuplicateTypeAlias(name) -> #(name, option.None)
    validator.CircularTypeAlias(name, _) -> #(name, option.None)
    validator.InvalidDictKeyTypeAlias(alias_name, _, _) -> #(
      alias_name,
      option.None,
    )
    validator.ExtendableOvershadowing(field_name, _, _) -> #(
      field_name,
      option.None,
    )
    validator.ExtendableTypeAliasNameCollision(name) -> #(name, option.None)
  }
  // Look up position of the name in source
  let #(line, column) = position_utils.find_name_position(source.content, name)
  let location =
    SourceLocation(
      line:,
      column:,
      end_column: option.Some(column + string.length(name)),
    )
  RichError(
    error: compilation_error,
    code: ErrorCode("validation", 200),
    source_path: option.Some(source.path),
    source_content: option.Some(source.content),
    location: option.Some(location),
    suggestion:,
  )
}
