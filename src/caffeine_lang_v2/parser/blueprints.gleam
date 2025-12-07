import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts.{type Artifact}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/set

pub type Blueprint {
  Blueprint(
    name: String,
    artifact: String,
    params: dict.Dict(String, helpers.AcceptedTypes),
    inputs: dict.Dict(String, Dynamic),
  )
}

pub fn blueprint_from_json(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(Blueprint, String) {
  let blueprint_decoder = {
    use name <- decode.field("name", decode.string)
    use artifact <- decode.field("artifact", decode.string)
    use params <- decode.field(
      "params",
      decode.dict(decode.string, helpers.accepted_types_decoder()),
    )

    use inputs <- decode.field(
      "inputs",
      decode.dict(decode.string, decode.dynamic),
    )

    decode.success(Blueprint(name:, artifact:, params:, inputs:))
  }
  use blueprint <- result.try(
    json.parse(from: json_string, using: blueprint_decoder)
    |> result.replace_error("Unable to JSON decode"),
  )

  use artifact <- result.try(
    case
      {
        artifacts
        |> list.filter(fn(art) { art.name == blueprint.artifact })
      }
    {
      [artifact] -> Ok(artifact)
      _ -> Error("Expected an artifact")
    },
  )

  let artifact_params =
    artifact.base_params
    |> dict.keys
    |> set.from_list

  let input_kets =
    blueprint.inputs
    |> dict.keys
    |> set.from_list

  use _ <- result.try(
    case
      set.is_subset(artifact_params, input_kets)
      && set.is_subset(input_kets, artifact_params)
    {
      True -> Ok(True)
      False -> Error("Different Keys")
    },
  )

  artifact_params
  |> set.to_list
  |> list.map(fn(key) {
    let assert Ok(expected_type) = artifact.base_params |> dict.get(key)
    let assert Ok(actual_value) = blueprint.inputs |> dict.get(key)

    case expected_type {
      helpers.Boolean -> decode.run(actual_value, decode.bool)
      helpers.Float ->
        case decode.run(actual_value, decode.float) {
          Ok(_) -> Ok(True)
          Error(err) -> Error(err)
        }
      helpers.Integer ->
        case decode.run(actual_value, decode.int) {
          Ok(_) -> Ok(True)
          Error(err) -> Error(err)
        }
      _ -> Ok(True)
    }
  })

  Ok(blueprint)
}
