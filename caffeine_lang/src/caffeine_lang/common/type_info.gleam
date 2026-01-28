import gleam/list
import gleam/string
import gleam_community/ansi

/// Type metadata for display purposes.
pub type TypeMeta {
  TypeMeta(name: String, description: String, syntax: String, example: String)
}

/// Pretty-prints a category with its types.
@internal
pub fn pretty_print_category(
  name: String,
  description: String,
  types: List(TypeMeta),
) -> String {
  let header =
    ansi.bold(ansi.cyan(name)) <> ": " <> ansi.dim("\"" <> description <> "\"")
  let type_entries =
    types
    |> list.map(pretty_print_type_meta)
    |> string.join("\n")

  header <> "\n\n" <> type_entries
}

/// Pretty-prints a single type entry.
fn pretty_print_type_meta(meta: TypeMeta) -> String {
  let name_line =
    "  "
    <> ansi.yellow(meta.name)
    <> ": "
    <> ansi.dim("\"" <> meta.description <> "\"")
  let syntax_line = "    syntax: " <> ansi.green(meta.syntax)
  let example_line = "    " <> ansi.blue("e.g. " <> meta.example)

  name_line <> "\n" <> syntax_line <> "\n" <> example_line
}
