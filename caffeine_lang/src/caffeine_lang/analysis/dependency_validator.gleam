import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/artifacts.{Hard}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, ir_to_identifier,
}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// Extracts depends_on from an IR's SloFields, if present.
fn get_depends_on(
  ir: IntermediateRepresentation(phase),
) -> Option(Dict(artifacts.DependencyRelationType, List(String))) {
  ir.get_slo_fields(ir.artifact_data)
  |> option.then(fn(slo) { slo.depends_on })
}

/// Validates that all dependency relations reference existing expectations.
///
/// Dependencies must be in the format "org.team.service.name" and must:
/// - Reference an expectation that exists in the compilation
/// - Not reference the expectation itself (no self-references)
/// - Not form circular dependency chains
/// - Satisfy composite hard dependency threshold constraints
@internal
pub fn validate_dependency_relations(
  irs: List(IntermediateRepresentation(ir.Linked)),
) -> Result(
  List(IntermediateRepresentation(ir.DepsValidated)),
  CompilationError,
) {
  // Build an index of all valid expectation paths
  let expectation_index = build_expectation_index(irs)

  // Validate each IR that has depends_on (accumulate all errors)
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
    |> list.filter(fn(ir) { option.is_some(get_depends_on(ir)) })
    |> list.map(fn(ir) {
      validate_single_ir_hard_thresholds(ir, expectation_index)
    })
    |> errors.from_results()
    |> result.map(fn(_) { Nil }),
  )

  // Promote phantom type from Linked to DepsValidated
  Ok(list.map(irs, ir.promote))
}

/// Builds an index of all expectation paths for quick lookup.
/// The path format is "org.team.service.name".
@internal
pub fn build_expectation_index(
  irs: List(IntermediateRepresentation(phase)),
) -> Dict(String, IntermediateRepresentation(phase)) {
  irs
  |> list.map(fn(ir) {
    let path = ir_to_identifier(ir)
    #(path, ir)
  })
  |> dict.from_list
}

fn validate_ir_dependencies(
  ir: IntermediateRepresentation(phase),
  expectation_index: Dict(String, IntermediateRepresentation(phase)),
) -> Result(Nil, CompilationError) {
  // Skip IRs that don't have depends_on
  let depends_on = get_depends_on(ir)
  use <- bool.guard(when: option.is_none(depends_on), return: Ok(Nil))

  let self_path = ir_to_identifier(ir)

  // Extract the relations from SloFields.depends_on.
  let assert option.Some(relations) = depends_on

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
        return: Error(errors.semantic_analysis_dependency_validation_error(
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
  expectation_index: Dict(String, IntermediateRepresentation(phase)),
) -> Result(Nil, CompilationError) {
  // First, validate the format
  case parse_dependency_path(target) {
    Error(Nil) ->
      Error(dependency_ref_error(
        target,
        self_path,
        "expected format 'org.team.service.name'",
      ))
    Ok(_) -> {
      // Check for self-reference
      use <- bool.guard(
        when: target == self_path,
        return: Error(dependency_ref_error(
          target,
          self_path,
          "self-reference not allowed",
        )),
      )
      // Check if target exists
      case dict.get(expectation_index, target) {
        Ok(_) -> Ok(Nil)
        Error(Nil) ->
          Error(dependency_ref_error(target, self_path, "target does not exist"))
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

/// Build a dependency reference error with a consistent message format.
fn dependency_ref_error(
  target: String,
  self_path: String,
  reason: String,
) -> CompilationError {
  errors.semantic_analysis_dependency_validation_error(
    msg: "Invalid dependency reference '"
    <> target
    <> "' in '"
    <> self_path
    <> "': "
    <> reason,
  )
}

// ==== Circular dependency detection ====

/// Builds a directed adjacency list from all IRs with depends_on.
fn build_adjacency_list(
  irs: List(IntermediateRepresentation(phase)),
) -> Dict(String, List(String)) {
  irs
  |> list.filter_map(fn(ir) {
    case get_depends_on(ir) {
      option.Some(relations) -> {
        let path = ir_to_identifier(ir)
        let targets = get_all_dependency_targets(relations)
        Ok(#(path, targets))
      }
      option.None -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Detects circular dependencies in the dependency graph.
fn detect_cycles(
  irs: List(IntermediateRepresentation(phase)),
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
        return: Error(errors.semantic_analysis_dependency_validation_error(
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

/// Validates hard dependency thresholds for a single IR using composite ceiling.
/// The composite ceiling is the product of all hard dependency thresholds,
/// representing the maximum achievable availability given those dependencies.
fn validate_single_ir_hard_thresholds(
  ir: IntermediateRepresentation(phase),
  expectation_index: Dict(String, IntermediateRepresentation(phase)),
) -> Result(Nil, CompilationError) {
  let self_path = ir_to_identifier(ir)
  use slo <- result.try(
    ir.get_slo_fields(ir.artifact_data)
    |> option.to_result(errors.semantic_analysis_dependency_validation_error(
      msg: self_path <> " - missing SLO artifact data",
    )),
  )
  let source_threshold = slo.threshold
  let hard_targets = case slo.depends_on {
    option.Some(relations) -> dict.get(relations, Hard) |> result.unwrap([])
    option.None -> []
  }

  let dep_thresholds =
    collect_hard_dep_thresholds(hard_targets, expectation_index)

  // Nothing to validate if no deps have SLO thresholds
  use <- bool.guard(when: list.is_empty(dep_thresholds), return: Ok(Nil))

  let composite_ceiling =
    compute_composite_ceiling(list.map(dep_thresholds, fn(pair) { pair.1 }))

  // Round ceiling to 4 decimal places for cleaner error messages
  let display_ceiling = round_to_4(composite_ceiling)

  case float.compare(source_threshold, composite_ceiling) {
    order.Gt -> {
      let deps_description =
        dep_thresholds
        |> list.map(fn(pair) {
          "'" <> pair.0 <> "' (" <> float.to_string(pair.1) <> ")"
        })
        |> string.join(", ")
      Error(errors.semantic_analysis_dependency_validation_error(
        msg: "Composite hard dependency threshold violation: '"
        <> self_path
        <> "' (threshold: "
        <> float.to_string(source_threshold)
        <> ") exceeds the composite availability ceiling of "
        <> float.to_string(display_ceiling)
        <> " from its hard dependencies: "
        <> deps_description,
      ))
    }
    _ -> Ok(Nil)
  }
}

/// Collects thresholds from hard dependency targets that have SLO fields.
/// Skips targets that don't exist in the index or don't have SLO data.
fn collect_hard_dep_thresholds(
  targets: List(String),
  expectation_index: Dict(String, IntermediateRepresentation(phase)),
) -> List(#(String, Float)) {
  targets
  |> list.filter_map(fn(target_path) {
    case dict.get(expectation_index, target_path) {
      Error(Nil) -> Error(Nil)
      Ok(target_ir) -> {
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

/// Rounds a float to 4 decimal places for cleaner display.
fn round_to_4(f: Float) -> Float {
  int.to_float(float.round(f *. 10_000.0)) /. 10_000.0
}
