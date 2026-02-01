import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/parser/artifacts.{type Artifact}
import caffeine_lang/parser/validations
import gleam/bool
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import gleam/string

/// A Blueprint that references one or more Artifacts with parameters and inputs. It provides further params
/// for the Expectation to satisfy while providing a partial set of inputs for the Artifact's params.
pub type Blueprint {
  Blueprint(
    name: String,
    artifact_refs: List(String),
    params: dict.Dict(String, AcceptedTypes),
    inputs: dict.Dict(String, Dynamic),
  )
}

/// Validates blueprints against artifacts and merges artifact params.
@internal
pub fn validate_blueprints(
  blueprints: List(Blueprint),
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  // Validate all names are unique.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    blueprints,
    by: fn(b) { b.name },
    label: "blueprint names",
  ))

  // Check for duplicate artifact refs within each blueprint.
  use _ <- result.try(validate_no_duplicate_artifact_refs(blueprints))

  // Map each blueprint to its list of artifacts.
  let blueprint_artifacts_collection =
    map_blueprints_to_artifacts(blueprints, artifacts)

  // Check for conflicting param types across artifacts in each blueprint.
  use _ <- result.try(validate_no_conflicting_params(
    blueprint_artifacts_collection,
  ))

  // Create merged params for each blueprint for input validation.
  let blueprint_merged_params_collection =
    blueprint_artifacts_collection
    |> list.map(fn(pair) {
      let #(blueprint, artifact_list) = pair
      let merged_params = merge_artifact_params(artifact_list)
      #(blueprint, merged_params)
    })

  // Validate exactly the right number of inputs and each input is the
  // correct type as per the param. A blueprint needs to specify inputs for
  // all required_params from the artifacts.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: blueprint_merged_params_collection,
    get_inputs: fn(blueprint) { blueprint.inputs },
    get_params: fn(merged_params) { merged_params },
    with: fn(blueprint) { "blueprint '" <> blueprint.name <> "'" },
    missing_inputs_ok: True,
  ))

  // Ensure no param name overshadowing by the blueprint against any artifact.
  use _ <- result.try(
    validations.validate_no_overshadowing(
      blueprint_merged_params_collection,
      get_check_collection: fn(blueprint) { blueprint.params },
      get_against_collection: fn(merged_params) { merged_params },
      get_error_label: fn(blueprint) {
        "blueprint '"
        <> blueprint.name
        <> "' - overshadowing inherited_params from artifact: "
      },
    ),
  )

  // At this point everything is validated, so we can merge params from all artifacts + blueprint params.
  let merged_param_blueprints =
    blueprint_artifacts_collection
    |> list.map(fn(blueprint_artifacts_pair) {
      let #(blueprint, artifact_list) = blueprint_artifacts_pair

      // Merge all params from all artifacts, then add blueprint params.
      let all_params =
        merge_artifact_params(artifact_list)
        |> dict.merge(blueprint.params)

      Blueprint(..blueprint, params: all_params)
    })

  Ok(merged_param_blueprints)
}

/// Map each blueprint to its list of referenced artifacts.
fn map_blueprints_to_artifacts(
  blueprints: List(Blueprint),
  artifacts: List(Artifact),
) -> List(#(Blueprint, List(Artifact))) {
  let artifact_map =
    artifacts
    |> list.map(fn(a) { #(artifacts.artifact_type_to_string(a.type_), a) })
    |> dict.from_list

  blueprints
  |> list.map(fn(blueprint) {
    let artifact_list =
      blueprint.artifact_refs
      |> list.filter_map(fn(ref) { dict.get(artifact_map, ref) })
    #(blueprint, artifact_list)
  })
}

/// Merge params from multiple artifacts into a single dict.
/// Extracts just the types from ParamInfo since blueprints work with types only.
fn merge_artifact_params(
  artifact_list: List(Artifact),
) -> dict.Dict(String, AcceptedTypes) {
  artifact_list
  |> list.fold(dict.new(), fn(acc, artifact) {
    dict.merge(acc, artifacts.params_to_types(artifact.params))
  })
}

/// Validate that no blueprint has duplicate artifact refs.
fn validate_no_duplicate_artifact_refs(
  blueprints: List(Blueprint),
) -> Result(Bool, CompilationError) {
  let duplicates =
    blueprints
    |> list.filter_map(fn(blueprint) {
      let refs = blueprint.artifact_refs
      let unique_refs = refs |> list.unique
      use <- bool.guard(
        when: list.length(refs) == list.length(unique_refs),
        return: Error(Nil),
      )
      // Find the duplicate(s)
      let duplicate_refs =
        refs
        |> list.group(fn(r) { r })
        |> dict.filter(fn(_, v) { list.length(v) > 1 })
        |> dict.keys
        |> string.join(", ")
      Ok(
        "blueprint '"
        <> blueprint.name
        <> "' - duplicate artifact references: "
        <> duplicate_refs,
      )
    })

  case duplicates {
    [] -> Ok(True)
    [first, ..] -> Error(errors.ParserDuplicateError(msg: first))
  }
}

/// Validate that artifacts referenced by a blueprint don't have conflicting param types.
fn validate_no_conflicting_params(
  blueprint_artifacts_collection: List(#(Blueprint, List(Artifact))),
) -> Result(Bool, CompilationError) {
  let conflicts =
    blueprint_artifacts_collection
    |> list.filter_map(fn(pair) {
      let #(blueprint, artifact_list) = pair
      case find_conflicting_params(artifact_list) {
        Ok(conflict) ->
          Ok(
            "blueprint '"
            <> blueprint.name
            <> "' - conflicting param types across artifacts: "
            <> conflict,
          )
        Error(Nil) -> Error(Nil)
      }
    })

  case conflicts {
    [] -> Ok(True)
    [first, ..] -> Error(errors.ParserDuplicateError(msg: first))
  }
}

/// Find param names that have different types across artifacts.
fn find_conflicting_params(artifact_list: List(Artifact)) -> Result(String, Nil) {
  // Collect all param name -> type mappings (extract types from ParamInfo)
  let all_params =
    artifact_list
    |> list.flat_map(fn(a) {
      a.params
      |> dict.to_list
      |> list.map(fn(pair) { #(pair.0, { pair.1 }.type_) })
    })

  // Group by param name
  let grouped =
    all_params
    |> list.group(fn(pair) { pair.0 })

  // Find conflicts (same name, different types)
  let conflicting_names =
    grouped
    |> dict.to_list
    |> list.filter_map(fn(group) {
      let #(name, pairs) = group
      let types = pairs |> list.map(fn(p) { p.1 })
      let unique_types = types |> list.unique
      case list.length(unique_types) > 1 {
        True -> Ok(name)
        False -> Error(Nil)
      }
    })

  case conflicting_names {
    [] -> Error(Nil)
    [first, ..] -> Ok(first)
  }
}
