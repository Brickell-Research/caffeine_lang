import caffeine_lang/common/errors.{type ParseError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import caffeine_lang/standard_library/artifacts
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
    // In some future world, it _may_ be important to protect this, maybe via an opaque type
    // however, for now we can just assume a Semver type and a parsing function will get us
    // most of the way. Especially true if Caffeine is the source of truth for artifacts via
    // the standard library for now.
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
  internal_parse_from_string(artifacts.standard_library)
}

/// Parses an artifact from an artifacts.json file.
pub fn parse_from_file(file_path: String) -> Result(List(Artifact), ParseError) {
  use json_string <- result.try(helpers.json_from_file(file_path))

  internal_parse_from_string(json_string)
}

/// The actual, common parsing logic.
fn internal_parse_from_string(
  content: String,
) -> Result(List(Artifact), ParseError) {
  use artifacts <- result.try(case parse_from_string(content) {
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

/// Parse a semantic version string (e.g., "1.2.3") into a Semver.
/// Only accepts non-negative integers without leading zeros.
@internal
pub fn parse_semver(version_string: String) -> Result(Semver, Nil) {
  case version_string |> string.split(".") |> list.map(parse_semver_part) {
    [Ok(major), Ok(minor), Ok(patch)] -> {
      Ok(Semver(major:, minor:, patch:))
    }
    _ -> Error(Nil)
  }
}

/// Parse a single semver part - must be non-negative and no leading zeros
/// (except for "0" itself).
fn parse_semver_part(s: String) -> Result(Int, Nil) {
  case s {
    "" -> Error(Nil)
    "0" -> Ok(0)
    _ ->
      case string.starts_with(s, "0") || string.starts_with(s, "-") {
        True -> Error(Nil)
        False -> int.parse(s)
      }
  }
}

/// Decoder for semantic version strings (e.g., "1.2.3").
fn semantic_version_decoder() -> decode.Decoder(Semver) {
  let err_default = Semver(0, 0, 0)
  decode.new_primitive_decoder("Semver", fn(dyn) {
    use str <- result.try(
      decode.run(dyn, decode.string) |> result.replace_error(err_default),
    )
    parse_semver(str) |> result.replace_error(err_default)
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
