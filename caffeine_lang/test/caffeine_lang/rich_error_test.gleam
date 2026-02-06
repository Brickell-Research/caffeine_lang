import caffeine_lang/errors
import caffeine_lang/rich_error.{ErrorCode, RichError}
import gleam/option
import gleeunit/should

// ==== error_code_to_string ====
// * ✅ three digit number
// * ✅ two digit number (pads)
// * ✅ single digit number (pads)
pub fn error_code_to_string_test() {
  rich_error.error_code_to_string(ErrorCode("parse", 103))
  |> should.equal("E103")

  rich_error.error_code_to_string(ErrorCode("cql", 42))
  |> should.equal("E042")

  rich_error.error_code_to_string(ErrorCode("test", 1))
  |> should.equal("E001")
}

// ==== error_code_for ====
// * ✅ frontend parse error
// * ✅ frontend validation error
// * ✅ semantic analysis error
// * ✅ codegen error
// * ✅ cql error
pub fn error_code_for_test() {
  errors.FrontendParseError("test")
  |> rich_error.error_code_for
  |> should.equal(ErrorCode("parse", 100))

  errors.FrontendValidationError("test")
  |> rich_error.error_code_for
  |> should.equal(ErrorCode("validation", 200))

  errors.SemanticAnalysisVendorResolutionError("test")
  |> rich_error.error_code_for
  |> should.equal(ErrorCode("semantic", 401))

  errors.GeneratorDatadogTerraformResolutionError("test")
  |> rich_error.error_code_for
  |> should.equal(ErrorCode("codegen", 502))

  errors.CQLParserError("test")
  |> rich_error.error_code_for
  |> should.equal(ErrorCode("cql", 602))
}

// ==== from_compilation_error ====
// * ✅ creates RichError with no location/suggestion
pub fn from_compilation_error_test() {
  let err = errors.FrontendParseError("test message")
  let rich = rich_error.from_compilation_error(err)
  rich
  |> should.equal(RichError(
    error: err,
    code: ErrorCode("parse", 100),
    source_path: option.None,
    source_content: option.None,
    location: option.None,
    suggestion: option.None,
  ))
}

// ==== error_message ====
// * ✅ extracts message from each variant
pub fn error_message_test() {
  errors.FrontendParseError("parse error msg")
  |> rich_error.error_message
  |> should.equal("parse error msg")

  errors.CQLResolverError("cql msg")
  |> rich_error.error_message
  |> should.equal("cql msg")
}
