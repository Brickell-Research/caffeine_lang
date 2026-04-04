import caffeine_lang/source_snippet.{SourceSnippet}
import gleam/option
import gleeunit/should

// ==== extract_snippet ====
// * ✅ error on middle line with context
// * ✅ error on first line
// * ✅ error on last line
// * ✅ single line source
// * ✅ multi-character span

pub fn extract_snippet_middle_line_test() {
  let source = "line one\nline two\nline three has error\nline four\nline five"
  let result = source_snippet.extract_snippet(source, 3, 16, option.Some(21))
  result
  |> should.equal(SourceSnippet(
    rendered: "2 | line two\n3 | line three has error\n  |                ^^^^^\n4 | line four",
  ))
}

pub fn extract_snippet_first_line_test() {
  let source = "error here\nsecond line\nthird line"
  let result = source_snippet.extract_snippet(source, 1, 1, option.Some(6))
  result
  |> should.equal(SourceSnippet(
    rendered: "1 | error here\n  | ^^^^^\n2 | second line",
  ))
}

pub fn extract_snippet_last_line_test() {
  let source = "first line\nsecond line\nerror here"
  let result = source_snippet.extract_snippet(source, 3, 7, option.None)
  result
  |> should.equal(SourceSnippet(
    rendered: "2 | second line\n3 | error here\n  |       ^",
  ))
}

pub fn extract_snippet_single_line_test() {
  let source = "only line"
  let result = source_snippet.extract_snippet(source, 1, 6, option.Some(10))
  result
  |> should.equal(SourceSnippet(rendered: "1 | only line\n  |      ^^^^"))
}

pub fn extract_snippet_wide_span_test() {
  let source = "aaa\nbbbbbbbbbb\nccc"
  let result = source_snippet.extract_snippet(source, 2, 1, option.Some(11))
  result
  |> should.equal(SourceSnippet(
    rendered: "1 | aaa\n2 | bbbbbbbbbb\n  | ^^^^^^^^^^\n3 | ccc",
  ))
}
