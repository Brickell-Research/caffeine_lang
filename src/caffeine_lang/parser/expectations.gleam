import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type ParseError, DuplicateError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/blueprints.{type Blueprint}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

pub type Expectation {
  Expectation(
    name: String,
    blueprint_ref: String,
    inputs: dict.Dict(String, Dynamic),
  )
}

pub fn parse_from_file(
  file_path: String,
  blueprints: List(Blueprint),
) -> Result(List(IntermediateRepresentation), ParseError) {
  // load file
  use json_string <- result.try(helpers.json_from_file(file_path))

  // actually parse
  use expectations <- result.try(
    case expectations_from_json(json_string, blueprints) {
      Ok(expectations) -> Ok(expectations)
      Error(err) -> Error(errors.format_json_decode_error(err))
    },
  )

  // map expectations to blueprints since we'll reuse that numerous times
  // and we've already validated all blueprint_refs
  let expectations_blueprint_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: blueprints,
      referrers: expectations,
      reference_name: fn(b) { b.name },
      referrer_reference: fn(e) { e.blueprint_ref },
    )

  // validate that expectation inputs don't overshadow blueprint inputs
  use _ <- result.try(check_input_overshadowing(
    expectations_blueprint_collection,
  ))

  // validate that expectation.inputs provides params NOT already provided by blueprint.inputs
  use _ <- result.try(
    validations.validate_inputs_for_collection(
      expectations_blueprint_collection,
      fn(expectation) { expectation.inputs },
      fn(blueprint) {
        let blueprint_input_keys = blueprint.inputs |> dict.keys
        blueprint.params
        |> dict.filter(fn(key, _) { !list.contains(blueprint_input_keys, key) })
      },
    ),
  )

  // validate unique names within a file
  use _ <- result.try(validations.validate_relevant_uniqueness(
    expectations,
    fn(e) { e.name },
    "expectation names",
  ))

  // build unique name prefix from file path
  let path_prefix = extract_path_prefix(file_path)

  // at this point we're completely validated, now build IR
  expectations_blueprint_collection
  |> list.map(fn(expectation_and_blueprint_pair) {
    let #(expectation, blueprint) = expectation_and_blueprint_pair

    // merge blueprint inputs with expectation inputs
    // Expectation inputs override blueprint inputs for the same key
    let merged_inputs = dict.merge(blueprint.inputs, expectation.inputs)

    let value_tuples =
      merged_inputs
      |> dict.keys
      |> list.map(fn(label) {
        // safe assertions since we're already validated everything
        let assert Ok(value) = merged_inputs |> dict.get(label)
        let assert Ok(typ) = blueprint.params |> dict.get(label)

        helpers.ValueTuple(label:, typ:, value:)
      })

    // build unique expectation name by combining path prefix with name
    let #(org, team, service) = path_prefix
    let service_name = service
    let unique_name = org <> "_" <> service_name <> "_" <> expectation.name

    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: expectation.name,
        org_name: org,
        service_name: service_name,
        blueprint_name: blueprint.name,
        team_name: team,
      ),
      unique_identifier: unique_name,
      artifact_ref: blueprint.artifact_ref,
      values: value_tuples,
      vendor: option.None,
    )
  })
  |> Ok
}

/// Extract a meaningful prefix from the source path
/// e.g., "examples/org/platform_team/authentication.json" -> #("org", "platform_team", "authentication")
@internal
pub fn extract_path_prefix(path: String) -> #(String, String, String) {
  case
    path
    |> string.split("/")
    |> list.reverse
    |> list.take(3)
    |> list.reverse
    |> list.map(fn(segment) {
      // Remove .json extension if present
      case string.ends_with(segment, ".json") {
        True -> string.drop_end(segment, 5)
        False -> segment
      }
    })
  {
    [org, team, service] -> #(org, team, service)
    // TODO: this should never happen, so we need to validate earlier in compilation
    _ -> #("unknown", "unknown", "unknown")
  }
}

fn check_input_overshadowing(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
) -> Result(Bool, ParseError) {
  let overshadow_errors =
    expectations_blueprint_collection
    |> list.filter_map(fn(pair) {
      let #(expectation, blueprint) = pair
      case
        validations.check_collection_key_overshadowing(
          expectation.inputs,
          blueprint.inputs,
          "Expectation '"
            <> expectation.name
            <> "' overshadowing inputs from blueprint: ",
        )
      {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  case overshadow_errors {
    "" -> Ok(True)
    _ -> Error(DuplicateError(msg: overshadow_errors))
  }
}

fn expectations_from_json(
  json_string: String,
  blueprints: List(Blueprint),
) -> Result(List(Expectation), json.DecodeError) {
  let expectation_decoded = {
    use name <- decode.field("name", decode.string)
    use blueprint_ref <- decode.field(
      "blueprint_ref",
      decoders.named_reference_decoder(blueprints, fn(b) { b.name }),
    )
    use inputs <- decode.field(
      "inputs",
      decode.dict(decode.string, decode.dynamic),
    )

    decode.success(Expectation(name:, blueprint_ref:, inputs:))
  }
  let expectations_decoded = {
    use expectations <- decode.field(
      "expectations",
      decode.list(expectation_decoded),
    )
    decode.success(expectations)
  }

  json.parse(from: json_string, using: expectations_decoded)
}
