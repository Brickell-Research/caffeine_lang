/// Frontend pipeline for compiling .caffeine source to JSON.
/// This module orchestrates the tokenizer, parser, validator, and generator
/// to transform .caffeine source into JSON for the compiler backend.
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/source_file.{type SourceFile}
import caffeine_lang/frontend/generator
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error
import caffeine_lang/frontend/validator
import gleam/json
import gleam/result

/// Compiles a blueprints .caffeine source to JSON string.
@internal
pub fn compile_blueprints(
  source: SourceFile,
) -> Result(String, CompilationError) {
  use ast <- result.try(
    parser.parse_blueprints_file(source.content)
    |> result.map_error(fn(err) {
      parser_error_to_compilation_error(err, source.path)
    }),
  )
  use validated <- result.try(
    validator.validate_blueprints_file(ast)
    |> result.map_error(fn(err) {
      validator_error_to_compilation_error(err, source.path)
    }),
  )
  Ok(json.to_string(generator.generate_blueprints_json(validated)))
}

/// Compiles an expects .caffeine source to JSON string.
@internal
pub fn compile_expects(
  source: SourceFile,
) -> Result(String, CompilationError) {
  use ast <- result.try(
    parser.parse_expects_file(source.content)
    |> result.map_error(fn(err) {
      parser_error_to_compilation_error(err, source.path)
    }),
  )
  use validated <- result.try(
    validator.validate_expects_file(ast)
    |> result.map_error(fn(err) {
      validator_error_to_compilation_error(err, source.path)
    }),
  )
  Ok(json.to_string(generator.generate_expects_json(validated)))
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

fn validator_error_to_string(err: validator.ValidatorError) -> String {
  case err {
    validator.DuplicateExtendable(name) -> "Duplicate extendable: " <> name
    validator.UndefinedExtendable(name, referenced_by) ->
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
    validator.UndefinedTypeAlias(name, referenced_by) ->
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
  }
}
