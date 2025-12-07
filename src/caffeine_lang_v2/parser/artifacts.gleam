import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

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

fn validate_relevant_uniqueness(
  artifacts: List(Artifact),
) -> Result(Bool, String) {
  let dupe_names =
    artifacts
    |> list.group(fn(artifact) { artifact.name })
    |> dict.filter(fn(_, occurrences) { list.length(occurrences) > 1 })
    |> dict.keys

  case dupe_names {
    [] -> Ok(True)
    _ ->
      Error("Duplicate artifact names: " <> { dupe_names |> string.join(", ") })
  }
}

pub fn parse_from_file(file_path) -> Result(List(Artifact), helpers.ParseError) {
  use json_string <- result.try(case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(helpers.FileReadError(msg: simplifile.describe_error(err)))
  })

  use artifacts <- result.try(case parse_from_string(json_string) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(helpers.format_json_decode_error(err))
  })

  case validate_relevant_uniqueness(artifacts) {
    Ok(_) -> Ok(artifacts)
    Error(err) -> Error(helpers.DuplicateError(err))
  }
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

pub fn parse_from_string(
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
