/// Frontend pipeline for compiling .caffeine source files.
/// Orchestrates the tokenizer, parser, validator, and generator
/// to transform .caffeine source into Blueprint and Expectation types.
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/source_file.{type SourceFile}
import caffeine_lang/frontend/generator
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error
import caffeine_lang/frontend/validator
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations.{type Expectation}
import gleam/result

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
    |> result.map_error(fn(err) {
      validator_error_to_compilation_error(err, source.path)
    }),
  )
  Ok(generator.generate_blueprints(validated))
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
    |> result.map_error(fn(err) {
      validator_error_to_compilation_error(err, source.path)
    }),
  )
  Ok(generator.generate_expectations(validated))
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
