import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/validations
import caffeine_lang/standard_library/artifacts
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/result

/// A reusable artifact template with named parameters.
pub type Artifact {
  Artifact(type_: ArtifactType, params: dict.Dict(String, AcceptedTypes))
}

/// Types of supported artifacts
pub type ArtifactType {
  SLO
  DependencyRelations
}

/// Parses the embedded standard library artifacts.
@internal
pub fn parse_standard_library() -> Result(List(Artifact), CompilationError) {
  parse_from_json_string(artifacts.standard_library)
}

/// Parses artifacts from a JSON string.
@internal
pub fn parse_from_json_string(
  content: String,
) -> Result(List(Artifact), CompilationError) {
  use artifacts <- result.try(case decode_artifacts_json(content) {
    Ok(artifacts) -> Ok(artifacts)
    Error(err) -> Error(errors.format_json_decode_error(err))
  })

  use _ <- result.try(validations.validate_relevant_uniqueness(
    artifacts,
    by: fn(a) { a.type_ |> artifact_type_to_string },
    label: "artifact names",
  ))

  Ok(artifacts)
}

/// Converts an ArtifactType to its corresponding string representation.
@internal
pub fn artifact_type_to_string(type_: ArtifactType) -> String {
  case type_ {
    SLO -> "SLO"
    DependencyRelations -> "DependencyRelations"
  }
}

/// Decoder for ArtifactType from a string.
fn artifact_type_decoder() -> decode.Decoder(ArtifactType) {
  use type_string <- decode.then(decode.string)
  case type_string {
    "SLO" -> decode.success(SLO)
    "DependencyRelations" -> decode.success(DependencyRelations)
    _ -> decode.failure(SLO, "SLO or DependencyRelations")
  }
}

fn decode_artifacts_json(
  json_string: String,
) -> Result(List(Artifact), json.DecodeError) {
  let artifact_decoder = {
    use type_ <- decode.field("type_", artifact_type_decoder())
    use params <- decode.field(
      "params",
      decode.dict(decode.string, decoders.accepted_types_decoder()),
    )

    decode.success(Artifact(type_:, params:))
  }
  let artifacts_decoded = {
    use artifacts <- decode.field("artifacts", decode.list(artifact_decoder))
    decode.success(artifacts)
  }

  json.parse(from: json_string, using: artifacts_decoded)
}
