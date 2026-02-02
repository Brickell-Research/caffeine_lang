import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

/// Generates a Mermaid flowchart string from dependency relations in IRs.
/// Nodes are grouped into subgraphs by service.
pub fn generate(irs: List(IntermediateRepresentation)) -> String {
  let subgraphs = build_subgraphs(irs)
  let edges = build_edges(irs)

  ["graph TD"]
  |> list.append(subgraphs)
  |> list.append(edges)
  |> string.join("\n")
}

/// Groups IRs by service and generates Mermaid subgraph blocks.
fn build_subgraphs(irs: List(IntermediateRepresentation)) -> List(String) {
  irs
  |> list.group(fn(ir) { service_key(ir) })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.flat_map(fn(group) {
    let #(service, group_irs) = group
    let header =
      "    subgraph "
      <> sanitize_id(service)
      <> "[\""
      <> escape_label(service)
      <> "\"]"
    let nodes = list.map(group_irs, build_node)
    list.flatten([[header], nodes, ["    end"]])
  })
}

/// Builds the service grouping key from IR metadata.
fn service_key(ir: IntermediateRepresentation) -> String {
  ir.metadata.service_name
}

/// Generates a single Mermaid node declaration with just the expectation name.
fn build_node(ir: IntermediateRepresentation) -> String {
  let path = ir_to_identifier(ir)
  let id = sanitize_id(path)
  let safe_name = escape_label(ir.metadata.friendly_label)
  "        " <> id <> "[\"" <> safe_name <> "\"]"
}

/// Generates Mermaid edge declarations for hard and soft dependencies.
fn build_edges(irs: List(IntermediateRepresentation)) -> List(String) {
  irs
  |> list.filter(fn(ir) {
    list.contains(ir.artifact_refs, artifacts.DependencyRelations)
  })
  |> list.flat_map(fn(ir) {
    let source_id = sanitize_id(ir_to_identifier(ir))
    let relations = helpers.extract_relations(ir.values)

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

/// Escapes characters that have special meaning in Mermaid labels.
/// Uses numeric HTML entity codes (e.g. #91; for [) which are broadly compatible.
fn escape_label(text: String) -> String {
  text
  |> string.replace("\"", "#34;")
  |> string.replace("[", "#91;")
  |> string.replace("]", "#93;")
  |> string.replace("(", "#40;")
  |> string.replace(")", "#41;")
  |> string.replace("{", "#123;")
  |> string.replace("}", "#125;")
  |> string.replace("<", "#60;")
  |> string.replace(">", "#62;")
}

/// Strips all non-alphanumeric characters (except underscores) for Mermaid-safe node IDs.
fn sanitize_id(path: String) -> String {
  path
  |> string.to_graphemes
  |> list.map(fn(g) {
    case g {
      "." | " " | "-" -> "_"
      _ -> {
        case is_id_char(g) {
          True -> g
          False -> ""
        }
      }
    }
  })
  |> string.concat
}

fn is_id_char(g: String) -> Bool {
  case g {
    "_" -> True
    _ ->
      case string.to_utf_codepoints(g) {
        [cp] -> {
          let code = string.utf_codepoint_to_int(cp)
          { code >= 65 && code <= 90 }
          || { code >= 97 && code <= 122 }
          || { code >= 48 && code <= 57 }
        }
        _ -> False
      }
  }
}
