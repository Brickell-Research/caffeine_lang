import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Artifact {
  Artifact(
    name: String,
    // for simplicity, don't enforce anything on version for now
    version: Semver,
    base_params: dict.Dict(String, helpers.AcceptedTypes),
    params: dict.Dict(String, helpers.AcceptedTypes),
  )
}

pub type Semver {
  Semver(major: Int, minor: Int, patch: Int)
}

pub fn parse_from_file(file_path) -> Result(List(Artifact), helpers.ParseError) {
  use json_string <- result.try(helpers.json_from_file(file_path))

  use artifacts <- result.try(case parse_from_string(json_string) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(helpers.format_json_decode_error(err))
  })

  use _ <- result.try(helpers.validate_relevant_uniqueness(
    artifacts,
    fn(a) { a.name },
    "artifact names",
  ))

  Ok(artifacts)
}

pub fn semantic_version_decoder() -> decode.Decoder(Semver) {
  decode.new_primitive_decoder("Semver", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) ->
        case x |> string.split(".") |> list.try_map(int.parse) {
          Ok([major, minor, patch]) -> Ok(Semver(major:, minor:, patch:))
          _ -> Error(Semver(0, 0, 0))
        }
      _ -> Error(Semver(0, 0, 0))
    }
  })
}

fn parse_from_string(
  json_string: String,
) -> Result(List(Artifact), json.DecodeError) {
  let artifact_decoder = {
    use name <- decode.field("name", decode.string)
    use version <- decode.field("version", semantic_version_decoder())
    use base_params <- decode.field(
      "base_params",
      decode.dict(decode.string, helpers.accepted_types_decoder()),
    )
    use params <- decode.field(
      "params",
      decode.dict(decode.string, helpers.accepted_types_decoder()),
    )

    decode.success(Artifact(name:, version:, base_params:, params:))
  }
  let artifacts_decoded = {
    use artifacts <- decode.field("artifacts", decode.list(artifact_decoder))
    decode.success(artifacts)
  }

  json.parse(from: json_string, using: artifacts_decoded)
}
