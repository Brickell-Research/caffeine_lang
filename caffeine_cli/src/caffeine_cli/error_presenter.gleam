/// Colorized error renderer for CLI output.
/// Applies ANSI color codes to RichError diagnostic output.
import caffeine_cli/color.{type ColorMode}
import caffeine_lang/errors.{type SourceLocation}
import caffeine_lang/rich_error.{type RichError}
import caffeine_lang/source_snippet
import gleam/int
import gleam/list
import gleam/option
import gleam/string

/// Renders a RichError with ANSI color codes.
pub fn render(error: RichError, color_mode: ColorMode) -> String {
  let code_str = rich_error.error_code_to_string(error.code)
  let msg = rich_error.error_message(error.error)

  // Header: error[E103]: message
  let header =
    color.bold(color.red("error[" <> code_str <> "]", color_mode), color_mode)
    <> ": "
    <> msg

  // Location: --> path:line:column
  let location_line = case error.source_path, error.location {
    option.Some(path), option.Some(loc) ->
      option.Some(
        "  "
        <> color.blue("--> ", color_mode)
        <> color.cyan(
          path
            <> ":"
            <> int.to_string(loc.line)
            <> ":"
            <> int.to_string(loc.column),
          color_mode,
        ),
      )
    option.Some(path), option.None ->
      option.Some(
        "  " <> color.blue("--> ", color_mode) <> color.cyan(path, color_mode),
      )
    _, _ -> option.None
  }

  // Source snippet with colored markers
  let snippet = case error.source_content, error.location {
    option.Some(content), option.Some(loc) ->
      option.Some(render_colored_snippet(content, loc, color_mode))
    _, _ -> option.None
  }

  // Suggestion: = help: Did you mean 'X'?
  let suggestion_line = case error.suggestion {
    option.Some(suggestion) ->
      option.Some(
        "   "
        <> color.cyan("= help:", color_mode)
        <> " Did you mean '"
        <> color.green(suggestion, color_mode)
        <> "'?",
      )
    option.None -> option.None
  }

  [option.Some(header), location_line, snippet, suggestion_line]
  |> list.filter_map(fn(opt) {
    case opt {
      option.Some(val) -> Ok(val)
      option.None -> Error(Nil)
    }
  })
  |> string.join("\n")
}

/// Renders a list of RichErrors with ANSI color codes.
pub fn render_all(errors: List(RichError), color_mode: ColorMode) -> String {
  errors
  |> list.map(render(_, color_mode))
  |> string.join("\n\n")
}

/// Renders a source snippet with colored line numbers and error markers.
fn render_colored_snippet(
  content: String,
  loc: SourceLocation,
  color_mode: ColorMode,
) -> String {
  let snippet =
    source_snippet.extract_snippet(
      content,
      loc.line,
      loc.column,
      loc.end_column,
    )
  // Apply color to the rendered snippet:
  // - Line numbers get blue
  // - Caret markers get red+bold
  snippet.rendered
  |> string.split("\n")
  |> list.map(fn(line) { colorize_snippet_line(line, color_mode) })
  |> string.join("\n")
}

/// Applies color to a single snippet line.
fn colorize_snippet_line(line: String, color_mode: ColorMode) -> String {
  // Marker lines contain only spaces, |, and ^ characters
  case is_marker_line(line) {
    True -> color.bold(color.red(line, color_mode), color_mode)
    False -> {
      // Color the line number portion (everything before " | ")
      case string.split_once(line, " | ") {
        Ok(#(gutter, content)) ->
          color.blue(gutter, color_mode) <> " | " <> content
        Error(_) -> line
      }
    }
  }
}

/// Checks if a line is a marker line (only spaces, |, and ^).
fn is_marker_line(line: String) -> Bool {
  string.contains(line, "^")
  && {
    line
    |> string.to_graphemes
    |> list.all(fn(c) { c == " " || c == "|" || c == "^" })
  }
}
