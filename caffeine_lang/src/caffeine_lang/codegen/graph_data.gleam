/// Structured graph data for dependency visualization.
/// Produces JSON-serializable types instead of Mermaid text,
/// enabling interactive graph rendering in IDE webviews.
import caffeine_lang/linker/artifacts.{DependencyRelations, Hard, Soft}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, type Resolved, ir_to_identifier,
}
import gleam/dict
import gleam/list
import gleam/option
import gleam/result

/// A node in the dependency graph representing a single expectation.
pub type GraphNode {
  GraphNode(
    id: String,
    label: String,
    service: String,
    org: String,
    team: String,
  )
}

/// A directed edge in the dependency graph.
pub type GraphEdge {
  GraphEdge(source: String, target: String, relation_type: String)
}

/// Complete graph data with nodes and edges.
pub type GraphData {
  GraphData(nodes: List(GraphNode), edges: List(GraphEdge))
}

/// Generates structured graph data from resolved IRs.
/// Nodes are derived from all IRs; edges come from DependencyRelations artifacts.
pub fn generate(irs: List(IntermediateRepresentation(Resolved))) -> GraphData {
  let nodes = build_nodes(irs)
  let edges = build_edges(irs)
  GraphData(nodes: nodes, edges: edges)
}

/// Builds graph nodes from all IRs.
fn build_nodes(
  irs: List(IntermediateRepresentation(Resolved)),
) -> List(GraphNode) {
  list.map(irs, fn(ir) {
    GraphNode(
      id: ir_to_identifier(ir),
      label: ir.metadata.friendly_label.value,
      service: ir.metadata.service_name.value,
      org: ir.metadata.org_name.value,
      team: ir.metadata.team_name.value,
    )
  })
}

/// Builds graph edges from IRs that have DependencyRelations.
fn build_edges(
  irs: List(IntermediateRepresentation(Resolved)),
) -> List(GraphEdge) {
  irs
  |> list.filter(fn(ir) { list.contains(ir.artifact_refs, DependencyRelations) })
  |> list.flat_map(fn(ir) {
    let source_id = ir_to_identifier(ir)
    case ir.get_dependency_fields(ir.artifact_data) {
      option.None -> []
      option.Some(dep) -> {
        let hard_edges =
          dict.get(dep.relations, Hard)
          |> result.unwrap([])
          |> list.map(fn(target) {
            GraphEdge(source: source_id, target: target, relation_type: "hard")
          })

        let soft_edges =
          dict.get(dep.relations, Soft)
          |> result.unwrap([])
          |> list.map(fn(target) {
            GraphEdge(source: source_id, target: target, relation_type: "soft")
          })

        list.append(hard_edges, soft_edges)
      }
    }
  })
}
