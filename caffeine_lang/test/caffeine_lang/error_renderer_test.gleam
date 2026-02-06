import caffeine_lang/error_renderer
import caffeine_lang/errors
import caffeine_lang/rich_error.{ErrorCode, RichError, SourceLocation}
import gleam/option
import gleeunit/should

// ==== render_plain ====
// * ✅ error with no location or suggestion
// * ✅ error with location and source snippet
// * ✅ error with location, snippet, and suggestion
// * ✅ error with path but no location

pub fn render_plain_no_location_test() {
  let err =
    RichError(
      error: errors.LinkerParseError("something went wrong"),
      code: ErrorCode("linker", 301),
      source_path: option.None,
      source_content: option.None,
      location: option.None,
      suggestion: option.None,
    )
  error_renderer.render_plain(err)
  |> should.equal("error[E301]: something went wrong")
}

pub fn render_plain_with_location_test() {
  let err =
    RichError(
      error: errors.FrontendParseError("Unknown type 'Strin'"),
      code: ErrorCode("parse", 103),
      source_path: option.Some("test.caffeine"),
      source_content: option.Some("line one\nenv: Strin\nline three"),
      location: option.Some(SourceLocation(
        line: 2,
        column: 6,
        end_column: option.Some(11),
      )),
      suggestion: option.None,
    )
  error_renderer.render_plain(err)
  |> should.equal(
    "error[E103]: Unknown type 'Strin'\n  --> test.caffeine:2:6\n1 | line one\n2 | env: Strin\n  |      ^^^^^\n3 | line three",
  )
}

pub fn render_plain_with_suggestion_test() {
  let err =
    RichError(
      error: errors.FrontendParseError("Unknown type 'Strin'"),
      code: ErrorCode("parse", 103),
      source_path: option.Some("test.caffeine"),
      source_content: option.Some("line one\nenv: Strin\nline three"),
      location: option.Some(SourceLocation(
        line: 2,
        column: 6,
        end_column: option.Some(11),
      )),
      suggestion: option.Some("String"),
    )
  error_renderer.render_plain(err)
  |> should.equal(
    "error[E103]: Unknown type 'Strin'\n  --> test.caffeine:2:6\n1 | line one\n2 | env: Strin\n  |      ^^^^^\n3 | line three\n   = help: Did you mean 'String'?",
  )
}

pub fn render_plain_path_no_location_test() {
  let err =
    RichError(
      error: errors.SemanticAnalysisVendorResolutionError("vendor issue"),
      code: ErrorCode("semantic", 401),
      source_path: option.Some("my/file.caffeine"),
      source_content: option.None,
      location: option.None,
      suggestion: option.None,
    )
  error_renderer.render_plain(err)
  |> should.equal("error[E401]: vendor issue\n  --> my/file.caffeine")
}
