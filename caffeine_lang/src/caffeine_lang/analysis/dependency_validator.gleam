import caffeine_lang/linker/ir.{type IntermediateRepresentation, ir_to_identifier}
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/artifacts.{DependencyRelations, Hard, SLO}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/option
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

  // Validate each IR that has DependencyRelations (accumulate all errors)
  use _ <- result.try(
    irs
    |> list.map(fn(ir) { validate_ir_dependencies(ir, expectation_index) })
    |> errors.from_results()
    |> result.map(fn(_) { Nil }),
  )

  // Detect circular dependencies
  use _ <- result.try(detect_cycles(irs))

  // Validate hard dependency thresholds (accumulate all errors)
  use _ <- result.try(
    irs
    |> list.filter(fn(ir) {
      list.contains(ir.artifact_refs, DependencyRelations)
      && list.contains(ir.artifact_refs, SLO)
    })
    |> list.map(fn(ir) {
      validate_single_ir_hard_thresholds(ir, expectation_index)
    })
    |> errors.from_results()
    |> result.map(fn(_) { Nil }),
  )

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

  // Extract the relations from structured artifact data.
  use dep <- result.try(
    ir.get_dependency_fields(ir.artifact_data)
    |> option.to_result(errors.SemanticAnalysisDependencyValidationError(
      msg: self_path <> " - missing dependency artifact data",
      context: errors.empty_context(),
    )),
  )
  let relations = dep.relations

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
  relations: Dict(artifacts.DependencyRelationType, List(String)),
) -> List(String) {
  relations
  |> dict.values
  |> list.flatten
}

fn check_for_duplicates_per_relation(
  relations: Dict(artifacts.DependencyRelationType, List(String)),
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
          context: errors.empty_context(),
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
        context: errors.empty_context(),
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
          context: errors.empty_context(),
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
            context: errors.empty_context(),
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
  |> list.filter_map(fn(ir) {
    case ir.get_dependency_fields(ir.artifact_data) {
      option.Some(dep) -> {
        let path = ir_to_identifier(ir)
        let targets = get_all_dependency_targets(dep.relations)
        Ok(#(path, targets))
      }
      option.None -> Error(Nil)
    }
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
          context: errors.empty_context(),
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

/// Validates hard dependency thresholds for a single IR using composite ceiling.
/// The composite ceiling is the product of all hard dependency thresholds,
/// representing the maximum achievable availability given those dependencies.
fn validate_single_ir_hard_thresholds(
  ir: IntermediateRepresentation,
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  let self_path = ir_to_identifier(ir)
  use #(slo, dep) <- result.try(
    case
      ir.get_slo_fields(ir.artifact_data),
      ir.get_dependency_fields(ir.artifact_data)
    {
      option.Some(slo), option.Some(dep) -> Ok(#(slo, dep))
      _, _ ->
        Error(errors.SemanticAnalysisDependencyValidationError(
          msg: self_path <> " - missing SLO or dependency artifact data",
          context: errors.empty_context(),
        ))
    },
  )
  let source_threshold = slo.threshold
  let hard_targets = dict.get(dep.relations, Hard) |> result.unwrap([])

  let dep_thresholds =
    collect_hard_dep_thresholds(hard_targets, expectation_index)

  // Nothing to validate if no deps have SLO thresholds
  use <- bool.guard(when: list.is_empty(dep_thresholds), return: Ok(Nil))

  let composite_ceiling =
    compute_composite_ceiling(list.map(dep_thresholds, fn(pair) { pair.1 }))

  case float.compare(source_threshold, composite_ceiling) {
    order.Gt -> {
      let deps_description =
        dep_thresholds
        |> list.map(fn(pair) {
          "'" <> pair.0 <> "' (" <> float.to_string(pair.1) <> ")"
        })
        |> string.join(", ")
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Composite hard dependency threshold violation: '"
          <> self_path
          <> "' (threshold: "
          <> float.to_string(source_threshold)
          <> ") exceeds the composite availability ceiling of "
          <> float.to_string(composite_ceiling)
          <> " from its hard dependencies: "
          <> deps_description,
        context: errors.empty_context(),
      ))
    }
    _ -> Ok(Nil)
  }
}

/// Collects thresholds from hard dependency targets that have SLO artifacts.
/// Skips targets that don't exist in the index or don't have SLO artifacts.
fn collect_hard_dep_thresholds(
  targets: List(String),
  expectation_index: Dict(String, IntermediateRepresentation),
) -> List(#(String, Float)) {
  targets
  |> list.filter_map(fn(target_path) {
    case dict.get(expectation_index, target_path) {
      Error(Nil) -> Error(Nil)
      Ok(target_ir) -> {
        use <- bool.guard(
          when: !list.contains(target_ir.artifact_refs, SLO),
          return: Error(Nil),
        )
        case ir.get_slo_fields(target_ir.artifact_data) {
          option.None -> Error(Nil)
          option.Some(slo) -> Ok(#(target_path, slo.threshold))
        }
      }
    }
  })
}

/// Computes the composite availability ceiling from a list of thresholds.
/// Each threshold is a percentage (e.g. 99.99). The composite ceiling is
/// the product of individual availabilities.
fn compute_composite_ceiling(thresholds: List(Float)) -> Float {
  list.fold(thresholds, 1.0, fn(acc, t) { acc *. { t /. 100.0 } }) *. 100.0
}
