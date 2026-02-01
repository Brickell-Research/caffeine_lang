import caffeine_lang/linker/artifacts.{type Artifact}
import caffeine_lang/types.{
  type AcceptedTypes, type TypeMeta, Defaulted, ModifierType, OneOf, Optional,
  RefinementType,
}
import gleam/dict
import gleam/list
import gleam/string
import gleam_community/ansi

/// Pretty-prints a category with its types for CLI display.
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

/// Pretty-prints an artifact showing its type, description, and parameters.
pub fn pretty_print_artifact(artifact: Artifact) -> String {
  let header =
    ansi.bold(ansi.cyan(artifacts.artifact_type_to_string(artifact.type_)))
    <> ": "
    <> ansi.dim("\"" <> artifact.description <> "\"")
  let params =
    artifact.params
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(pair) {
      let #(name, param_info) = pair
      "  "
      <> ansi.yellow(name)
      <> ": "
      <> ansi.dim("\"" <> param_info.description <> "\"")
      <> "\n    type: "
      <> ansi.green(types.accepted_type_to_string(param_info.type_))
      <> "\n    "
      <> param_status(param_info.type_)
    })
    |> string.join("\n")

  header <> "\n\n" <> params
}

/// Returns the status of a parameter: "required", "optional", or "default: <value>".
fn param_status(typ: AcceptedTypes) -> String {
  case typ {
    ModifierType(Optional(_)) -> ansi.dim("optional")
    ModifierType(Defaulted(_, default)) -> ansi.blue("default: " <> default)
    RefinementType(OneOf(inner, _)) -> param_status(inner)
    _ -> ansi.magenta("required")
  }
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
