import caffeine_lang/error_renderer
import caffeine_lang/errors.{ErrorContext, SourceLocation}
import gleam/option
import gleeunit/should

// ==== render_plain ====
// * ✅ error with no location or suggestion
// * ✅ error with location and source snippet
// * ✅ error with location, snippet, and suggestion
// * ✅ error with path but no location

pub fn render_plain_no_location_test() {
  let err =
    errors.LinkerParseError(
      msg: "something went wrong",
      context: errors.empty_context(),
    )
  error_renderer.render_plain(err)
  |> should.equal("error[E301]: something went wrong")
}

pub fn render_plain_with_location_test() {
  let err =
    errors.FrontendParseError(
      msg: "Unknown type 'Strin'",
      context: ErrorContext(
        identifier: option.None,
        source_path: option.Some("test.caffeine"),
        source_content: option.Some("line one\nenv: Strin\nline three"),
        location: option.Some(SourceLocation(
          line: 2,
          column: 6,
          end_column: option.Some(11),
        )),
        suggestion: option.None,
      ),
    )
  error_renderer.render_plain(err)
  |> should.equal(
    "error[E100]: Unknown type 'Strin'\n  --> test.caffeine:2:6\n1 | line one\n2 | env: Strin\n  |      ^^^^^\n3 | line three",
  )
}

pub fn render_plain_with_suggestion_test() {
  let err =
    errors.FrontendParseError(
      msg: "Unknown type 'Strin'",
      context: ErrorContext(
        identifier: option.None,
        source_path: option.Some("test.caffeine"),
        source_content: option.Some("line one\nenv: Strin\nline three"),
        location: option.Some(SourceLocation(
          line: 2,
          column: 6,
          end_column: option.Some(11),
        )),
        suggestion: option.Some("String"),
      ),
    )
  error_renderer.render_plain(err)
  |> should.equal(
    "error[E100]: Unknown type 'Strin'\n  --> test.caffeine:2:6\n1 | line one\n2 | env: Strin\n  |      ^^^^^\n3 | line three\n   = help: Did you mean 'String'?",
  )
}

pub fn render_plain_path_no_location_test() {
  let err =
    errors.LinkerVendorResolutionError(
      msg: "vendor issue",
      context: ErrorContext(
        identifier: option.None,
        source_path: option.Some("my/file.caffeine"),
        source_content: option.None,
        location: option.None,
        suggestion: option.None,
      ),
    )
  error_renderer.render_plain(err)
  |> should.equal("error[E304]: vendor issue\n  --> my/file.caffeine")
}

// ==== render_all_plain ====
// * ✅ empty list → empty string
// * ✅ single error → same as render_plain
// * ✅ multiple errors → joined with double newline
pub fn render_all_plain_empty_test() {
  error_renderer.render_all_plain([])
  |> should.equal("")
}

pub fn render_all_plain_single_test() {
  let err =
    errors.LinkerParseError(
      msg: "something broke",
      context: errors.empty_context(),
    )
  error_renderer.render_all_plain([err])
  |> should.equal("error[E301]: something broke")
}

pub fn render_all_plain_multiple_test() {
  let err1 =
    errors.FrontendParseError(
      msg: "parse failure",
      context: errors.empty_context(),
    )
  let err2 =
    errors.LinkerParseError(
      msg: "link failure",
      context: errors.empty_context(),
    )
  error_renderer.render_all_plain([err1, err2])
  |> should.equal("error[E100]: parse failure\n\nerror[E301]: link failure")
}
