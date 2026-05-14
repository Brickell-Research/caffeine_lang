/// Frontend pipeline for compiling .caffeine source files.
/// Orchestrates the tokenizer, parser, validator, and lowering
/// to transform .caffeine source into Measurement and Expectation types.
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/frontend/lowering
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error
import caffeine_lang/frontend/validator
import caffeine_lang/linker/expectations.{type Expectation}
import caffeine_lang/linker/measurements.{type Measurement, type Raw}
import caffeine_lang/source_file.{
  type ExpectationSource, type MeasurementSource, type SourceFile,
}
import gleam/list
import gleam/result

/// Compiles a measurements .caffeine source to a list of raw (unvalidated) measurements.
@internal
pub fn compile_measurements(
  source: SourceFile(MeasurementSource),
) -> Result(List(Measurement(Raw)), CompilationError) {
  use ast <- result.try(
    parser.parse_measurements_file(source.content)
    |> result.map_error(errs_to_compilation_error(
      _,
      source.path,
      parser_error.to_string,
      errors.frontend_parse_error,
    )),
  )
  use validated <- result.try(
    validator.validate_measurements_file(ast)
    |> result.map_error(errs_to_compilation_error(
      _,
      source.path,
      validator.error_to_string,
      errors.frontend_validation_error,
    )),
  )
  Ok(lowering.lower_measurements(validated))
}

/// Compiles an expects .caffeine source to a list of expectations.
@internal
pub fn compile_expects(
  source: SourceFile(ExpectationSource),
) -> Result(List(Expectation), CompilationError) {
  use ast <- result.try(
    parser.parse_expects_file(source.content)
    |> result.map_error(errs_to_compilation_error(
      _,
      source.path,
      parser_error.to_string,
      errors.frontend_parse_error,
    )),
  )
  use validated <- result.try(
    validator.validate_expects_file(ast)
    |> result.map_error(errs_to_compilation_error(
      _,
      source.path,
      validator.error_to_string,
      errors.frontend_validation_error,
    )),
  )
  Ok(lowering.lower_expectations(validated))
}

/// Converts a list of stage-specific errors to a CompilationError, parameterised
/// by the renderer and the smart-constructor for the wrapping error kind.
fn errs_to_compilation_error(
  errs: List(err),
  file_path: String,
  to_string: fn(err) -> String,
  make: fn(String) -> CompilationError,
) -> CompilationError {
  let to_compilation = fn(err) { make(file_path <> ": " <> to_string(err)) }
  case errs {
    [single] -> to_compilation(single)
    multiple ->
      errors.CompilationErrors(errors: list.map(multiple, to_compilation))
  }
}
