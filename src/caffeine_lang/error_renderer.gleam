/// Plain-text error renderer (no ANSI codes).
/// Composes error code, message, location, source snippet, and suggestion
/// into Rust/Elm-style diagnostic output.
import caffeine_lang/errors.{type CompilationError, type SourceLocation}
import caffeine_lang/source_snippet
import gleam/int
import gleam/list
import gleam/option
import gleam/string

/// Renders a CompilationError to a plain-text diagnostic string.
pub fn render_plain(error: CompilationError) -> String {
  let code_str = errors.error_code_to_string(errors.error_code_for(error))
  let msg = errors.to_message(error)
  let ctx = errors.error_context(error)

  // Header line: error[E103]: message
  let header = "error[" <> code_str <> "]: " <> msg

  // Location line: --> path:line:column
  let location_line = case ctx.source_path, ctx.location {
    option.Some(path), option.Some(loc) ->
      option.Some(
        "  --> "
        <> path
        <> ":"
        <> int.to_string(loc.line)
        <> ":"
        <> int.to_string(loc.column),
      )
    option.Some(path), option.None -> option.Some("  --> " <> path)
    _, _ -> option.None
  }

  // Source snippet
  let snippet = case ctx.source_content, ctx.location {
    option.Some(content), option.Some(loc) ->
      option.Some(render_snippet(content, loc))
    _, _ -> option.None
  }

  // Suggestion line
  let suggestion_line = case ctx.suggestion {
    option.Some(suggestion) ->
      option.Some("   = help: Did you mean '" <> suggestion <> "'?")
    option.None -> option.None
  }

  // Compose all parts
  [option.Some(header), location_line, snippet, suggestion_line]
  |> list.filter_map(fn(opt) {
    case opt {
      option.Some(val) -> Ok(val)
      option.None -> Error(Nil)
    }
  })
  |> string.join("\n")
}

/// Renders a list of CompilationErrors to a plain-text string.
pub fn render_all_plain(errors: List(CompilationError)) -> String {
  errors
  |> list.map(render_plain)
  |> string.join("\n\n")
}

/// Renders a source snippet for the given content and location.
fn render_snippet(content: String, loc: SourceLocation) -> String {
  let snippet =
    source_snippet.extract_snippet(
      content,
      loc.line,
      loc.column,
      loc.end_column,
    )
  snippet.rendered
}
