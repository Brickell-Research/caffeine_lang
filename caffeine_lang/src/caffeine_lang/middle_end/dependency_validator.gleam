import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// Validates that all dependency relations reference existing expectations.
///
/// Dependencies must be in the format "org.team.service.name" and must:
/// - Reference an expectation that exists in the compilation
/// - Not reference the expectation itself (no self-references)
@internal
pub fn validate_dependency_relations(
  irs: List(IntermediateRepresentation),
) -> Result(List(IntermediateRepresentation), CompilationError) {
  // Build an index of all valid expectation paths
  let expectation_index = build_expectation_index(irs)

  // Validate each IR that has DependencyRelations
  use _ <- result.try(
    irs
    |> list.try_each(fn(ir) {
      validate_ir_dependencies(ir, expectation_index)
    }),
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
    let path = ir_to_path(ir)
    #(path, ir)
  })
  |> dict.from_list
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

fn validate_ir_dependencies(
  ir: IntermediateRepresentation,
  expectation_index: Dict(String, IntermediateRepresentation),
) -> Result(Nil, CompilationError) {
  // Skip IRs that don't have DependencyRelations
  use <- bool.guard(
    when: !list.contains(ir.artifact_refs, "DependencyRelations"),
    return: Ok(Nil),
  )

  let self_path = ir_to_path(ir)

  // Extract the relations value from the IR
  let relations = extract_relations(ir)

  // Get all dependency targets (from both hard and soft)
  let all_targets = get_all_dependency_targets(relations)

  // Check for duplicates
  use _ <- result.try(check_for_duplicates(all_targets, self_path))

  // Validate each target
  all_targets
  |> list.try_each(fn(target) {
    validate_dependency_target(target, self_path, expectation_index)
  })
}

fn extract_relations(
  ir: IntermediateRepresentation,
) -> Dict(String, List(String)) {
  ir.values
  |> list.filter(fn(vt) { vt.label == "relations" })
  |> list.first
  |> result.try(fn(vt) {
    decode.run(
      vt.value,
      decode.dict(decode.string, decode.list(decode.string)),
    )
    |> result.replace_error(Nil)
  })
  |> result.unwrap(dict.new())
}

fn get_all_dependency_targets(relations: Dict(String, List(String))) -> List(String) {
  relations
  |> dict.values
  |> list.flatten
}

fn check_for_duplicates(
  targets: List(String),
  self_path: String,
) -> Result(Nil, CompilationError) {
  do_check_for_duplicates(targets, set.new(), self_path)
}

fn do_check_for_duplicates(
  targets: List(String),
  seen: set.Set(String),
  self_path: String,
) -> Result(Nil, CompilationError) {
  case targets {
    [] -> Ok(Nil)
    [target, ..rest] -> {
      use <- bool.guard(when: set.contains(seen, target), return: Error(
        errors.SemanticAnalysisDependencyValidationError(
          msg: "Duplicate dependency reference '"
            <> target
            <> "' in '"
            <> self_path
            <> "'",
        ),
      ))
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
      use <- bool.guard(when: target == self_path, return: Error(
        errors.SemanticAnalysisDependencyValidationError(
          msg: "Invalid dependency reference '"
            <> target
            <> "' in '"
            <> self_path
            <> "': self-reference not allowed",
        ),
      ))
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
