import caffeine_lang/analysis/semantic_analyzer.{
  type IntermediateRepresentation, ir_to_identifier,
}
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{DependencyRelations, SLO}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// Validates that all dependency relations reference existing expectations.
///
/// Dependencies must be in the format "org.team.service.name" and must:
/// - Reference an expectation that exists in the compilation
/// - Not reference the expectation itself (no self-references)
/// - Not form circular dependency chains
/// - Satisfy hard dependency threshold constraints (source <= target)
@internal
pub fn validate_dependency_relations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  // Build an index of all valid expectation paths
  let expectation_index = build_expectation_index(irs)

  // Validate each IR that has DependencyRelations
  use _ <- result.try(
    irs
    |> list.try_each(fn(ir) { validate_ir_dependencies(ir, expectation_index) }),
  )

  // Detect circular dependencies
  use _ <- result.try(detect_cycles(irs))

  // Validate hard dependency thresholds
  use _ <- result.try(validate_hard_dependency_thresholds(
    irs,
    expectation_index,
  ))

  Ok(irs)
}

/// Builds an index of all expectation paths for quick lookup.
/// The path format is "org.team.service.name".
@internal
pub fn build_expectation_index(
  irs: List(IntermediateRepresentation),
) -> Dict(String, IntermediateRepresentation) {
  irs
  |> list.map(fn(ir) {
    let path = ir_to_identifier(ir)
    #(path, ir)
  })
  |> dict.from_list
}

fn validate_ir_dependencies(
  ir: IntermediateRepresentation,
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  // Skip IRs that don't have DependencyRelations
  use <- bool.guard(
    when: !list.contains(ir.artifact_refs, DependencyRelations),
    return: Ok(Nil),
  )

  let self_path = ir_to_identifier(ir)

  // Extract the relations value from the IR
  let relations = helpers.extract_relations(ir.values)

  // Check for duplicates within each relation type (hard and soft independently)
  use _ <- result.try(check_for_duplicates_per_relation(relations, self_path))

  // Get all dependency targets (from both hard and soft) for further validation
  let all_targets = get_all_dependency_targets(relations)

  // Validate each target
  all_targets
  |> list.try_each(fn(target) {
    validate_dependency_target(target, self_path, expectation_index)
  })
}

fn get_all_dependency_targets(
  relations: Dict(String, List(String)),
) -> List(String) {
  relations
  |> dict.values
  |> list.flatten
}

fn check_for_duplicates_per_relation(
  relations: Dict(String, List(String)),
  self_path: String,
) -> Result(Nil, CompilationError) {
  relations
  |> dict.to_list
  |> list.try_each(fn(pair) {
    let #(_, targets) = pair
    do_check_for_duplicates(targets, set.new(), self_path)
  })
}

fn do_check_for_duplicates(
  targets: List(String),
  seen: set.Set(String),
  self_path: String,
) -> Result(Nil, CompilationError) {
  case targets {
    [] -> Ok(Nil)
    [target, ..rest] -> {
      use <- bool.guard(
        when: set.contains(seen, target),
        return: Error(errors.SemanticAnalysisDependencyValidationError(
          msg: "Duplicate dependency reference '"
          <> target
          <> "' in '"
          <> self_path
          <> "'",
        )),
      )
      do_check_for_duplicates(rest, set.insert(seen, target), self_path)
    }
  }
}

fn validate_dependency_target(
  target: String,
  self_path: String,
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  // First, validate the format
  case parse_dependency_path(target) {
    Error(Nil) ->
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Invalid dependency reference '"
        <> target
        <> "' in '"
        <> self_path
        <> "': expected format 'org.team.service.name'",
      ))
    Ok(_) -> {
      // Check for self-reference
      use <- bool.guard(
        when: target == self_path,
        return: Error(errors.SemanticAnalysisDependencyValidationError(
          msg: "Invalid dependency reference '"
          <> target
          <> "' in '"
          <> self_path
          <> "': self-reference not allowed",
        )),
      )
      // Check if target exists
      case dict.get(expectation_index, target) {
        Ok(_) -> Ok(Nil)
        Error(Nil) ->
          Error(errors.SemanticAnalysisDependencyValidationError(
            msg: "Invalid dependency reference '"
            <> target
            <> "' in '"
            <> self_path
            <> "': target does not exist",
          ))
      }
    }
  }
}

/// Parses a dependency path into its components (org, team, service, name).
/// Returns Error if the path doesn't have exactly 4 non-empty parts.
@internal
pub fn parse_dependency_path(
  path: String,
) -> Result(#(String, String, String, String), Nil) {
  case string.split(path, ".") {
    [org, team, service, name]
      if org != "" && team != "" && service != "" && name != ""
    -> Ok(#(org, team, service, name))
    _ -> Error(Nil)
  }
}

// ==== Circular dependency detection ====

/// Builds a directed adjacency list from all IRs with DependencyRelations.
fn build_adjacency_list(
  irs: List(IntermediateRepresentation),
) -> Dict(String, List(String)) {
  irs
  |> list.filter(fn(ir) { list.contains(ir.artifact_refs, DependencyRelations) })
  |> list.map(fn(ir) {
    let path = ir_to_identifier(ir)
    let relations = helpers.extract_relations(ir.values)
    let targets = get_all_dependency_targets(relations)
    #(path, targets)
  })
  |> dict.from_list
}

/// Detects circular dependencies in the dependency graph.
fn detect_cycles(
  irs: List(IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  let adjacency = build_adjacency_list(irs)
  let nodes =
    adjacency
    |> dict.keys
    |> list.sort(string.compare)

  detect_cycles_loop(nodes, adjacency, set.new(), set.new())
  |> result.map(fn(_) { Nil })
}

fn detect_cycles_loop(
  nodes: List(String),
  adjacency: Dict(String, List(String)),
  visited: Set(String),
  in_progress: Set(String),
) -> Result(Set(String), CompilationError) {
  case nodes {
    [] -> Ok(visited)
    [node, ..rest] -> {
      // Skip already fully visited nodes
      use <- bool.guard(
        when: set.contains(visited, node),
        return: detect_cycles_loop(rest, adjacency, visited, in_progress),
      )

      // Explore this node via DFS
      use #(visited, in_progress) <- result.try(
        explore_node(node, adjacency, visited, in_progress, [node]),
      )

      detect_cycles_loop(rest, adjacency, visited, in_progress)
    }
  }
}

fn explore_node(
  node: String,
  adjacency: Dict(String, List(String)),
  visited: Set(String),
  in_progress: Set(String),
  path: List(String),
) -> Result(#(Set(String), Set(String)), CompilationError) {
  let in_progress = set.insert(in_progress, node)
  let neighbors = dict.get(adjacency, node) |> result.unwrap([])

  use #(visited, in_progress) <- result.try(explore_neighbors(
    neighbors,
    adjacency,
    visited,
    in_progress,
    path,
  ))

  // Mark node as fully visited, remove from in-progress
  let visited = set.insert(visited, node)
  let in_progress = set.delete(in_progress, node)
  Ok(#(visited, in_progress))
}

fn explore_neighbors(
  neighbors: List(String),
  adjacency: Dict(String, List(String)),
  visited: Set(String),
  in_progress: Set(String),
  path: List(String),
) -> Result(#(Set(String), Set(String)), CompilationError) {
  case neighbors {
    [] -> Ok(#(visited, in_progress))
    [neighbor, ..rest] -> {
      // Cycle detected: neighbor is on the current DFS path
      use <- bool.guard(
        when: set.contains(in_progress, neighbor),
        return: Error(errors.SemanticAnalysisDependencyValidationError(
          msg: "Circular dependency detected: "
          <> string.join(list.reverse(path), " -> ")
          <> " -> "
          <> neighbor,
        )),
      )

      // Skip already fully visited nodes, otherwise recurse
      use <- bool.guard(
        when: set.contains(visited, neighbor),
        return: explore_neighbors(rest, adjacency, visited, in_progress, path),
      )
      use #(visited, in_progress) <- result.try(
        explore_node(neighbor, adjacency, visited, in_progress, [
          neighbor,
          ..path
        ]),
      )

      explore_neighbors(rest, adjacency, visited, in_progress, path)
    }
  }
}

// ==== Hard dependency threshold validation ====

/// Validates that hard dependency thresholds are consistent.
/// A source's threshold must not exceed its hard dependency's threshold.
fn validate_hard_dependency_thresholds(
  irs: List(IntermediateRepresentation),
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  irs
  |> list.filter(fn(ir) {
    list.contains(ir.artifact_refs, DependencyRelations)
    && list.contains(ir.artifact_refs, SLO)
  })
  |> list.try_each(fn(ir) {
    let self_path = ir_to_identifier(ir)
    let source_threshold = helpers.extract_threshold(ir.values)
    let relations = helpers.extract_relations(ir.values)
    let hard_targets = dict.get(relations, "hard") |> result.unwrap([])

    hard_targets
    |> list.try_each(fn(target) {
      validate_single_hard_threshold(
        self_path,
        source_threshold,
        target,
        expectation_index,
      )
    })
  })
}

fn validate_single_hard_threshold(
  source_path: String,
  source_threshold: Float,
  target_path: String,
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  case dict.get(expectation_index, target_path) {
    Error(Nil) -> Ok(Nil)
    Ok(target_ir) -> {
      // Only validate if target also has SLO artifact
      use <- bool.guard(
        when: !list.contains(target_ir.artifact_refs, SLO),
        return: Ok(Nil),
      )

      let target_threshold = helpers.extract_threshold(target_ir.values)

      // Use float.compare for proper floating point comparison
      case float.compare(source_threshold, target_threshold) {
        order.Gt ->
          Error(errors.SemanticAnalysisDependencyValidationError(
            msg: "Hard dependency threshold violation: '"
            <> source_path
            <> "' (threshold: "
            <> float.to_string(source_threshold)
            <> ") cannot exceed its hard dependency '"
            <> target_path
            <> "' (threshold: "
            <> float.to_string(target_threshold)
            <> ")",
          ))
        _ -> Ok(Nil)
      }
    }
  }
}
