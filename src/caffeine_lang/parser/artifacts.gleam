import caffeine_lang/common/errors.{type ParseError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// The standard library artifacts embedded at compile time.
/// This ensures the binary is self-contained and doesn't need external files.
const standard_library_artifacts = "
{
  \"artifacts\": [
    {
      \"name\": \"SLO\",
      \"version\": \"0.0.1\",
      \"base_params\": { \"threshold\": \"Float\", \"window_in_days\": \"Integer\" },
      \"params\": { \"queries\": \"Dict(String, String)\", \"value\": \"String\", \"vendor\": \"String\"}
    }
  ]
}
"

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

/// Parses the embedded standard library artifacts.
pub fn parse_standard_library() -> Result(List(Artifact), ParseError) {
  // actually parse
  use artifacts <- result.try(case parse_from_string(standard_library_artifacts) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(errors.format_json_decode_error(err))
  })

  // validate names are unique
  use _ <- result.try(validations.validate_relevant_uniqueness(
    artifacts,
    fn(a) { a.name },
    "artifact names",
  ))

  // return success
  Ok(artifacts)
}

pub fn parse_from_file(file_path) -> Result(List(Artifact), ParseError) {
  // load file
  use json_string <- result.try(helpers.json_from_file(file_path))

  // actually parse
  use artifacts <- result.try(case parse_from_string(json_string) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(errors.format_json_decode_error(err))
  })

  // validate names are unique
  use _ <- result.try(validations.validate_relevant_uniqueness(
    artifacts,
    fn(a) { a.name },
    "artifact names",
  ))

  // return success
  Ok(artifacts)
}

/// Decoder for semantic version strings (e.g., "1.2.3").
pub fn semantic_version_decoder() -> decode.Decoder(Semver) {
  let err_default = Semver(0, 0, 0)
  decode.new_primitive_decoder("Semver", fn(dyn) {
    use str <- result.try(
      decode.run(dyn, decode.string) |> result.replace_error(err_default),
    )
    case str |> string.split(".") |> list.try_map(int.parse) {
      Ok([major, minor, patch]) -> Ok(Semver(major:, minor:, patch:))
      _ -> Error(err_default)
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
