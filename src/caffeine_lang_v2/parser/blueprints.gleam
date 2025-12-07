import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import gleam/string

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
  use json_string <- result.try(helpers.json_from_file(file_path))

  use blueprints <- result.try(
    case blueprints_from_json(json_string, artifacts) {
      Ok(blueprints) -> Ok(blueprints)
      Error(err) -> Error(helpers.format_json_decode_error(err))
    },
  )

  // map blueprints to artifacts since we'll reuse that numerous times
  // and we've already validated all artifact_refs
  let blueprint_artifact_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: artifacts,
      referrers: blueprints,
      reference_name: fn(a) { a.name },
      referrer_reference: fn(b) { b.artifact_ref },
    )

  use _ <- result.try(
    helpers.validate_inputs_for_collection(
      blueprint_artifact_collection,
      fn(blueprint) { blueprint.inputs },
      fn(artifact) { artifact.params },
    ),
  )

  use _ <- result.try(helpers.validate_relevant_uniqueness(
    blueprints,
    fn(b) { b.name },
    "blueprint names",
  ))

  let overshadow_params_error =
    blueprint_artifact_collection
    |> list.filter_map(fn(blueprint_artifact_pair) {
      let #(blueprint, artifact) = blueprint_artifact_pair

      case check_base_param_overshadowing(blueprint, artifact) {
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

  // at this point everything is validated, so we can merge base_params, params, and artifact params
  let merged_param_blueprints =
    blueprint_artifact_collection
    |> list.map(fn(blueprint_artifact_pair) {
      let #(blueprint, artifact) = blueprint_artifact_pair

      // Merge all params: artifact.params + artifact.base_params + blueprint.params
      let all_params =
        artifact.params
        |> dict.merge(artifact.base_params)
        |> dict.merge(blueprint.params)

      Blueprint(..blueprint, params: all_params)
    })

  Ok(merged_param_blueprints)
}

fn check_base_param_overshadowing(
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

pub fn blueprints_from_json(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), json.DecodeError) {
  let blueprint_decoded = {
    use name <- decode.field("name", decode.string)
    use artifact_ref <- decode.field(
      "artifact_ref",
      helpers.named_reference_decoder(artifacts, fn(a) { a.name }),
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
