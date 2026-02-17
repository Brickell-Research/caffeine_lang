import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/rich_error.{ErrorCode, RichError}
import gleam/option
import gleeunit/should
import test_helpers

// ==== error_code_to_string ====
// * ✅ three digit number
// * ✅ two digit number (pads)
// * ✅ single digit number (pads)
pub fn error_code_to_string_test() {
  [
    #("three digit number", ErrorCode("parse", 103), "E103"),
    #("two digit number (pads)", ErrorCode("cql", 42), "E042"),
    #("single digit number (pads)", ErrorCode("test", 1), "E001"),
  ]
  |> test_helpers.table_test_1(rich_error.error_code_to_string)
}

// ==== error_code_for ====
// * ✅ frontend parse error
// * ✅ frontend validation error
// * ✅ semantic analysis error
// * ✅ codegen error
// * ✅ cql error
pub fn error_code_for_test() {
  [
    #(
      "frontend parse error",
      errors.FrontendParseError(msg: "test", context: errors.empty_context()),
      ErrorCode("parse", 100),
    ),
    #(
      "frontend validation error",
      errors.FrontendValidationError(
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("validation", 200),
    ),
    #(
      "semantic analysis error",
      errors.LinkerVendorResolutionError(
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("linker", 304),
    ),
    #(
      "codegen error",
      errors.GeneratorTerraformResolutionError(
        vendor: constants.vendor_datadog,
        msg: "test",
        context: errors.empty_context(),
      ),
      ErrorCode("codegen", 502),
    ),
    #(
      "cql error",
      errors.CQLParserError(msg: "test", context: errors.empty_context()),
      ErrorCode("cql", 602),
    ),
  ]
  |> test_helpers.table_test_1(rich_error.error_code_for)
}

// ==== from_compilation_error ====
// * ✅ creates RichError with no location/suggestion
pub fn from_compilation_error_test() {
  let err =
    errors.FrontendParseError(
      msg: "test message",
      context: errors.empty_context(),
    )
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
  [
    #(
      "extracts message from parse error",
      errors.FrontendParseError(
        msg: "parse error msg",
        context: errors.empty_context(),
      ),
      "parse error msg",
    ),
    #(
      "extracts message from cql error",
      errors.CQLResolverError(msg: "cql msg", context: errors.empty_context()),
      "cql msg",
    ),
  ]
  |> test_helpers.table_test_1(rich_error.error_message)
}
