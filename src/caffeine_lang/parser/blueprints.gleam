import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import caffeine_lang/parser/artifacts.{type Artifact}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
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

/// Parse blueprints from a file.
@internal
pub fn parse_from_json_file(
  file_path: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  use json_string <- result.try(helpers.json_from_file(file_path))

  parse_from_json_string(json_string, artifacts)
}

/// Parse blueprints from a JSON string.
@internal
pub fn parse_from_json_string(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  use blueprints <- result.try(
    case blueprints_from_json(json_string, artifacts) {
      Ok(blueprints) -> Ok(blueprints)
      Error(err) -> Error(errors.format_json_decode_error(err))
    },
  )

  validate_blueprints(blueprints, artifacts)
}

/// Validates and transforms blueprints after JSON parsing.
/// This performs all the validation and merging that parse_from_file does,
/// but takes already-parsed blueprints instead of reading from a file.
@internal
pub fn validate_blueprints(
  blueprints: List(Blueprint),
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  // Validate all names are unique.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    blueprints,
    fn(b) { b.name },
    "blueprint names",
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

  // Create a synthetic merged artifact for each blueprint for input validation.
  let blueprint_merged_artifact_collection =
    blueprint_artifacts_collection
    |> list.map(fn(pair) {
      let #(blueprint, artifact_list) = pair
      let merged_params = merge_artifact_params(artifact_list)
      #(blueprint, artifacts.Artifact(name: "merged", params: merged_params))
    })

  // Validate exactly the right number of inputs and each input is the
  // correct type as per the param. A blueprint needs to specify inputs for
  // all required_params from the artifacts.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: blueprint_merged_artifact_collection,
    get_inputs: fn(blueprint) { blueprint.inputs },
    get_params: fn(artifact) { artifact.params },
    missing_inputs_ok: True,
  ))

  // Ensure no param name overshadowing by the blueprint against any artifact.
  let overshadow_params_error =
    blueprint_merged_artifact_collection
    |> list.filter_map(fn(blueprint_artifact_pair) {
      let #(blueprint, merged_artifact) = blueprint_artifact_pair

      case
        validations.check_collection_key_overshadowing(
          blueprint.params,
          merged_artifact.params,
          "Blueprint overshadowing inherited_params from artifact: ",
        )
      {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  use _ <- result.try(case overshadow_params_error {
    "" -> Ok(True)
    _ ->
      Error(errors.ParserDuplicateError(
        msg: "Overshadowed inherited_params in blueprint error: "
        <> overshadow_params_error,
      ))
  })

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
    |> list.map(fn(a) { #(a.name, a) })
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
fn merge_artifact_params(
  artifact_list: List(Artifact),
) -> dict.Dict(String, AcceptedTypes) {
  artifact_list
  |> list.fold(dict.new(), fn(acc, artifact) {
    dict.merge(acc, artifact.params)
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
      case list.length(refs) == list.length(unique_refs) {
        True -> Error(Nil)
        False -> {
          // Find the duplicate(s)
          let duplicate_refs =
            refs
            |> list.group(fn(r) { r })
            |> dict.filter(fn(_, v) { list.length(v) > 1 })
            |> dict.keys
            |> string.join(", ")
          Ok(duplicate_refs)
        }
      }
    })

  case duplicates {
    [] -> Ok(True)
    [first, ..] ->
      Error(errors.ParserDuplicateError(
        msg: "Duplicate artifact references in blueprint: " <> first,
      ))
  }
}

/// Validate that artifacts referenced by a blueprint don't have conflicting param types.
fn validate_no_conflicting_params(
  blueprint_artifacts_collection: List(#(Blueprint, List(Artifact))),
) -> Result(Bool, CompilationError) {
  let conflicts =
    blueprint_artifacts_collection
    |> list.filter_map(fn(pair) {
      let #(_blueprint, artifact_list) = pair
      find_conflicting_params(artifact_list)
    })

  case conflicts {
    [] -> Ok(True)
    [first, ..] ->
      Error(errors.ParserDuplicateError(
        msg: "Conflicting param types across artifacts: " <> first,
      ))
  }
}

/// Find param names that have different types across artifacts.
fn find_conflicting_params(artifacts: List(Artifact)) -> Result(String, Nil) {
  // Collect all param name -> type mappings
  let all_params =
    artifacts
    |> list.flat_map(fn(a) { dict.to_list(a.params) })

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

/// Decodes a list of blueprints from a JSON dynamic value.
@internal
pub fn blueprints_from_json(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), json.DecodeError) {
  let blueprint_decoded = {
    use name <- decode.field("name", decoders.non_empty_string_decoder())
    use artifact_refs <- decode.field(
      "artifact_refs",
      decoders.non_empty_named_reference_list_decoder(artifacts, fn(a) {
        a.name
      }),
    )
    use params <- decode.field(
      "params",
      decode.dict(decode.string, decoders.accepted_types_decoder()),
    )
    use inputs <- decode.field(
      "inputs",
      decode.dict(decode.string, decode.dynamic),
    )

    decode.success(Blueprint(name:, artifact_refs:, params:, inputs:))
  }
  let blueprints_decoded = {
    use blueprints <- decode.field("blueprints", decode.list(blueprint_decoded))
    decode.success(blueprints)
  }

  json.parse(from: json_string, using: blueprints_decoded)
}
