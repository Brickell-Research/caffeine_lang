import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import simplifile

pub type Blueprint {
  Blueprint(
    name: String,
    artifact_ref: String,
    params: dict.Dict(String, helpers.AcceptedTypes),
    inputs: dict.Dict(String, Dynamic),
  )
}

pub fn parse_from_file(
  file_path: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), helpers.ParseError) {
  use json_string <- result.try(case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(helpers.FileReadError(msg: simplifile.describe_error(err)))
  })

  use blueprints <- result.try(
    case blueprints_from_json(json_string, artifacts) {
      Ok(blueprints) -> Ok(blueprints)
      Error(err) -> Error(helpers.format_json_decode_error(err))
    },
  )

  let input_validations_error =
    blueprints
    |> list.filter_map(fn(blueprint) {
      let inputs = blueprint.inputs
      // already performed this check so can assert it
      let assert Ok(artifact) =
        artifacts
        |> list.filter(fn(artifact) { artifact.name == blueprint.artifact_ref })
        |> list.first
      let params = artifact.params

      case inputs_validator(params:, inputs:) {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  use _ <- result.try(case input_validations_error {
    "" -> Ok(True)
    _ ->
      Error(helpers.JsonParserError(
        "Input validation errors: " <> input_validations_error,
      ))
  })

  use _ <- result.try(case validate_relevant_uniqueness(blueprints) {
    Ok(_) -> Ok(blueprints)
    Error(err) -> Error(helpers.DuplicateError(err))
  })

  // merge base_params and params
  let overshadow_params_error =
    blueprints
    |> list.filter_map(fn(blueprint) {
      // already performed this check so can assert it
      let assert Ok(artifact) =
        artifacts
        |> list.filter(fn(artifact) { artifact.name == blueprint.artifact_ref })
        |> list.first

      case check_base_param_oversahdowing(blueprint, artifact) {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  use _ <- result.try(case overshadow_params_error {
    "" -> Ok(True)
    _ ->
      Error(helpers.DuplicateError(
        "Overshadowed base_params in blueprint error: "
        <> overshadow_params_error,
      ))
  })

  let merged_param_blueprints =
    blueprints
    |> list.map(fn(blueprint) {
      // already performed this check so can assert it
      let assert Ok(artifact) =
        artifacts
        |> list.filter(fn(artifact) { artifact.name == blueprint.artifact_ref })
        |> list.first

      Blueprint(
        ..blueprint,
        params: dict.merge(blueprint.params, artifact.base_params),
      )
    })

  Ok(merged_param_blueprints)
}

fn check_base_param_oversahdowing(
  blueprint: Blueprint,
  artifact: Artifact,
) -> Result(Bool, String) {
  let blueprint_param_names = blueprint.params |> dict.keys |> set.from_list
  let artifact_param_names = artifact.base_params |> dict.keys |> set.from_list
  let overshadowing_params = {
    set.intersection(blueprint_param_names, artifact_param_names) |> set.to_list
  }

  case overshadowing_params {
    [] -> Ok(True)
    _ ->
      Error(
        "Blueprint overshadowing base_params from artifact: "
        <> overshadowing_params |> string.join(", "),
      )
  }
}

fn validate_relevant_uniqueness(
  blueprints: List(Blueprint),
) -> Result(Bool, String) {
  let dupe_names =
    blueprints
    |> list.group(fn(artifact) { artifact.name })
    |> dict.filter(fn(_, occurrences) { list.length(occurrences) > 1 })
    |> dict.keys

  case dupe_names {
    [] -> Ok(True)
    _ ->
      Error("Duplicate artifact names: " <> { dupe_names |> string.join(", ") })
  }
}

fn artifact_ref_decoder(artifacts: List(Artifact)) {
  let artifact_names = artifacts |> list.map(fn(artifact) { artifact.name })

  decode.new_primitive_decoder("ArtifactReference", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) -> {
        case artifact_names |> list.contains(x) {
          True -> Ok(x)
          False -> Error("")
        }
      }
      _ -> Error("")
    }
  })
}

fn inputs_validator(
  params params: Dict(String, helpers.AcceptedTypes),
  inputs inputs: Dict(String, dynamic.Dynamic),
) -> Result(Bool, String) {
  let param_keys = params |> dict.keys |> set.from_list
  let input_keys = inputs |> dict.keys |> set.from_list

  let keys_only_in_params =
    set.difference(param_keys, input_keys) |> set.to_list
  let keys_only_in_inputs =
    set.difference(input_keys, param_keys) |> set.to_list

  // see if we have the same inputs and params
  use _ <- result.try(case keys_only_in_params, keys_only_in_inputs {
    [], [] -> Ok(True)
    _, [] ->
      Error(
        "Missing keys in input: "
        <> { keys_only_in_params |> string.join(", ") },
      )
    [], _ ->
      Error(
        "Extra keys in input: " <> { keys_only_in_inputs |> string.join(", ") },
      )
    _, _ ->
      Error(
        "Extra keys in input: "
        <> { keys_only_in_inputs |> string.join(", ") }
        <> " and missing keys in input: "
        <> { keys_only_in_params |> string.join(", ") },
      )
  })

  let type_validation_errors =
    inputs
    |> dict.to_list
    |> list.filter_map(fn(pair) {
      let #(key, value) = pair
      let assert Ok(expected_type) = params |> dict.get(key)

      case helpers.validate_value_type(value, expected_type) {
        Ok(_) -> Error(Nil)
        Error(errs) -> Ok(errs)
      }
    })
    |> list.map(fn(err) { err.msg })
    |> string.join(", ")

  case type_validation_errors {
    "" -> Ok(True)
    _ -> Error(type_validation_errors)
  }
}

pub fn blueprints_from_json(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), json.DecodeError) {
  let blueprint_decoded = {
    use name <- decode.field("name", decode.string)
    use artifact_ref <- decode.field(
      "artifact_ref",
      artifact_ref_decoder(artifacts),
    )
    use params <- decode.field(
      "params",
      decode.dict(decode.string, helpers.accepted_types_decoder()),
    )
    use inputs <- decode.field(
      "inputs",
      decode.dict(decode.string, decode.dynamic),
    )

    decode.success(Blueprint(name:, artifact_ref:, params:, inputs:))
  }
  let blueprints_decoded = {
    use blueprints <- decode.field("blueprints", decode.list(blueprint_decoded))
    decode.success(blueprints)
  }

  json.parse(from: json_string, using: blueprints_decoded)
}
