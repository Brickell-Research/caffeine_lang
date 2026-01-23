import caffeine_lang/common/decoders
import caffeine_lang/common/errors.{type CompilationError}
import caffeine_lang/common/helpers
import caffeine_lang/common/validations
import caffeine_lang/parser/blueprints.{type Blueprint}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// An Expectation is a concrete implementation of an Artifact + Blueprint.
pub type Expectation {
  Expectation(
    name: String,
    blueprint_ref: String,
    inputs: dict.Dict(String, Dynamic),
  )
}

/// Parse expectations from a JSON string.
@internal
pub fn parse_from_json_string(
  json_string: String,
  blueprints: List(Blueprint),
) -> Result(List(#(Expectation, Blueprint)), CompilationError) {
  // Parse the JSON string.
  use expectations <- result.try(
    case expectations_from_json(json_string, blueprints) {
      Ok(expectations) -> Ok(expectations)
      Error(err) -> Error(errors.format_json_decode_error(err))
    },
  )

  validate_expectations(expectations, blueprints)
}

/// Parse expectations from a JSON string.
@internal
pub fn expectations_from_json(
  json_string: String,
  blueprints: List(Blueprint),
) -> Result(List(Expectation), json.DecodeError) {
  let expectation_decoded = {
    use name <- decode.field("name", decoders.non_empty_string_decoder())
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

/// Validate expectations and return paired with their blueprints.
/// TODO: This provides massive duplication and is an area of low hanging fruit for optimization.
fn validate_expectations(
  expectations: List(Expectation),
  blueprints: List(Blueprint),
) -> Result(List(#(Expectation, Blueprint)), CompilationError) {
  // Map expectations to blueprints since we'll reuse that numerous times
  // and we've already validated all blueprint_refs.
  let expectations_blueprint_collection =
    helpers.map_reference_to_referrer_over_collection(
      references: blueprints,
      referrers: expectations,
      reference_name: fn(b) { b.name },
      referrer_reference: fn(e) { e.blueprint_ref },
    )

  // Validate that expectation inputs don't overshadow blueprint inputs.
  use _ <- result.try(check_input_overshadowing(
    expectations_blueprint_collection,
  ))

  // Validate that expectation.inputs provides params NOT already provided by blueprint.inputs.
  use _ <- result.try(validations.validate_inputs_for_collection(
    input_param_collections: expectations_blueprint_collection,
    get_inputs: fn(expectation) { expectation.inputs },
    get_params: fn(blueprint) {
      let blueprint_input_keys = blueprint.inputs |> dict.keys
      blueprint.params
      |> dict.filter(fn(key, _) { !list.contains(blueprint_input_keys, key) })
    },
    missing_inputs_ok: False,
  ))

  // Validate unique names within a file.
  use _ <- result.try(validations.validate_relevant_uniqueness(
    expectations,
    fn(e) { e.name },
    "expectation names",
  ))

  Ok(expectations_blueprint_collection)
}

fn check_input_overshadowing(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
) -> Result(Bool, CompilationError) {
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
    _ -> Error(errors.ParserDuplicateError(msg: overshadow_errors))
  }
}
