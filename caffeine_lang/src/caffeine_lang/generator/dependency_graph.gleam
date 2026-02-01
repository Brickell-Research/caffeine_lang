import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/list
import gleam/result
import gleam/string

/// Generates a Mermaid flowchart string from dependency relations in IRs.
pub fn generate(irs: List(IntermediateRepresentation)) -> String {
  let nodes = build_nodes(irs)
  let edges = build_edges(irs)

  ["graph LR"]
  |> list.append(nodes)
  |> list.append(edges)
  |> string.join("\n")
}

/// Generates Mermaid node declarations with path and threshold labels.
fn build_nodes(irs: List(IntermediateRepresentation)) -> List(String) {
  irs
  |> list.map(fn(ir) {
    let path = ir_to_path(ir)
    let id = sanitize_id(path)
    let threshold = extract_threshold(ir)
    let label = path <> "\\n(threshold: " <> float.to_string(threshold) <> ")"
    "    " <> id <> "[\"" <> label <> "\"]"
  })
}

/// Generates Mermaid edge declarations for hard and soft dependencies.
fn build_edges(irs: List(IntermediateRepresentation)) -> List(String) {
  irs
  |> list.filter(fn(ir) {
    list.contains(ir.artifact_refs, "DependencyRelations")
  })
  |> list.flat_map(fn(ir) {
    let source_id = sanitize_id(ir_to_path(ir))
    let relations = extract_relations(ir)

    let hard_edges =
      dict.get(relations, "hard")
      |> result.unwrap([])
      |> list.map(fn(target) {
        "    " <> source_id <> " -->|hard| " <> sanitize_id(target)
      })

    let soft_edges =
      dict.get(relations, "soft")
      |> result.unwrap([])
      |> list.map(fn(target) {
        "    " <> source_id <> " -.->|soft| " <> sanitize_id(target)
      })

    list.append(hard_edges, soft_edges)
  })
}

/// Replaces dots with underscores for Mermaid-safe node IDs.
fn sanitize_id(path: String) -> String {
  string.replace(path, ".", "_")
}

fn ir_to_path(ir: IntermediateRepresentation) -> String {
  ir.metadata.org_name
  <> "."
  <> ir.metadata.team_name
  <> "."
  <> ir.metadata.service_name
  <> "."
  <> ir.metadata.friendly_label
}

fn extract_threshold(ir: IntermediateRepresentation) -> Float {
  helpers.extract_value(ir.values, "threshold", decode.float)
  |> result.unwrap(99.9)
}

fn extract_relations(
  ir: IntermediateRepresentation,
) -> dict.Dict(String, List(String)) {
  ir.values
  |> list.filter(fn(vt) { vt.label == "relations" })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.dict(decode.string, decode.list(decode.string)))
    |> result.replace_error(Nil)
  })
  |> result.unwrap(dict.new())
}
