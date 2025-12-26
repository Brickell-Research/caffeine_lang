import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import caffeine_lang/standard_library/artifacts
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub type Artifact {
  Artifact(name: String, params: dict.Dict(String, AcceptedTypes))
}

/// Parses the embedded standard library artifacts.
pub fn parse_standard_library() -> Result(List(Artifact), CompilationError) {
  internal_parse_from_json_string(artifacts.standard_library)
}

/// Parses an artifact from an artifacts.json file.
pub fn parse_from_json_file(
  file_path: String,
) -> Result(List(Artifact), CompilationError) {
  use json_string <- result.try(helpers.json_from_file(file_path))

  internal_parse_from_json_string(json_string)
}

/// The actual, common parsing logic.
fn internal_parse_from_json_string(
  content: String,
) -> Result(List(Artifact), CompilationError) {
  use artifacts <- result.try(case parse_from_json_string(content) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(errors.format_json_decode_error(err))
  })

  use _ <- result.try(validations.validate_relevant_uniqueness(
    artifacts,
    fn(a) { a.name },
    "artifact names",
  ))

  Ok(artifacts)
}

fn parse_from_json_string(
  json_string: String,
) -> Result(List(Artifact), json.DecodeError) {
  let artifact_decoder = {
    use name <- decode.field("name", decoders.non_empty_string_decoder())
    use params <- decode.field(
      "params",
      decode.dict(decode.string, decoders.accepted_types_decoder()),
    )

    decode.success(Artifact(name:, params:))
  }
  let artifacts_decoded = {
    use artifacts <- decode.field("artifacts", decode.list(artifact_decoder))
    decode.success(artifacts)
  }

  json.parse(from: json_string, using: artifacts_decoded)
}
