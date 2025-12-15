import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type CompilationError, ParserDuplicateError}
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

pub type Blueprint {
  Blueprint(
    name: String,
    artifact_ref: String,
    params: dict.Dict(String, helpers.AcceptedTypes),
    inputs: dict.Dict(String, Dynamic),
  )
}

/// Parse blueprints from a file.
pub fn parse_from_file(
  file_path: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  use json_string <- result.try(helpers.json_from_file(file_path))

  parse_from_string(json_string, artifacts)
}

/// Parse blueprints from a JSON string.
/// This is public so it can be used by browser.gleam for in-browser compilation.
pub fn parse_from_string(
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
pub fn validate_blueprints(
  blueprints: List(Blueprint),
  artifacts: List(Artifact),
) -> Result(List(Blueprint), CompilationError) {
  // map blueprints to artifacts since we'll reuse that numerous times
  let blueprint_artifact_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: artifacts,
      referrers: blueprints,
      reference_name: fn(a) { a.name },
      referrer_reference: fn(b) { b.artifact_ref },
    )

  // validate exactly the right number of inputs and each input is the
  // correct type as per the param. A blueprint needs to specify inputs for
  // all required_params from the artifact.
  use _ <- result.try(
    validations.validate_inputs_for_collection(
      blueprint_artifact_collection,
      fn(blueprint) { blueprint.inputs },
      fn(artifact) { artifact.required_params },
    ),
  )

  // validate all names are unique
  use _ <- result.try(validations.validate_relevant_uniqueness(
    blueprints,
    fn(b) { b.name },
    "blueprint names",
  ))

  // ensure no param name overshadowing by the blueprint
  let overshadow_params_error =
    blueprint_artifact_collection
    |> list.filter_map(fn(blueprint_artifact_pair) {
      let #(blueprint, artifact) = blueprint_artifact_pair

      case
        validations.check_collection_key_overshadowing(
          blueprint.params,
          artifact.inherited_params,
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
      Error(ParserDuplicateError(
        "Overshadowed inherited_params in blueprint error: "
        <> overshadow_params_error,
      ))
  })

  // at this point everything is validated, so we can merge inherited_params, params, and artifact required_params
  let merged_param_blueprints =
    blueprint_artifact_collection
    |> list.map(fn(blueprint_artifact_pair) {
      let #(blueprint, artifact) = blueprint_artifact_pair

      // Merge all params: artifact.required_params + artifact.inherited_params + blueprint.params
      let all_params =
        artifact.required_params
        |> dict.merge(artifact.inherited_params)
        |> dict.merge(blueprint.params)

      Blueprint(..blueprint, params: all_params)
    })

  Ok(merged_param_blueprints)
}

pub fn blueprints_from_json(
  json_string: String,
  artifacts: List(Artifact),
) -> Result(List(Blueprint), json.DecodeError) {
  let blueprint_decoded = {
    use name <- decode.field("name", decoders.non_empty_string_decoder())
    use artifact_ref <- decode.field(
      "artifact_ref",
      decoders.named_reference_decoder(artifacts, fn(a) { a.name }),
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
