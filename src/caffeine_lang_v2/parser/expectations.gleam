import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/middle_end.{type IntermediateRepresentation}
import caffeine_lang_v2/parser/blueprints.{type Blueprint}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

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
) -> Result(List(IntermediateRepresentation), helpers.ParseError) {
  use json_string <- result.try(case simplifile.read(file_path) {
    Ok(file_contents) -> Ok(file_contents)
    Error(err) ->
      Error(helpers.FileReadError(msg: simplifile.describe_error(err)))
  })

  use expectations <- result.try(
    case expectations_from_json(json_string, blueprints) {
      Ok(expectations) -> Ok(expectations)
      Error(err) -> Error(helpers.format_json_decode_error(err))
    },
  )

  // map expectations to blueprints since we'll reuse that numerous times
  // and we've already validated all blueprint_refs
  let expectations_blueprint_collection =
    expectations
    |> list.map(fn(expectation) {
      // already performed this check so can assert it
      let assert Ok(blueprint) =
        blueprints
        |> list.filter(fn(blueprint) {
          blueprint.name == expectation.blueprint_ref
        })
        |> list.first
      #(expectation, blueprint)
    })

  let input_validations_error =
    expectations_blueprint_collection
    |> list.filter_map(fn(blueprint_artifact_pair) {
      let #(expectation, blueprint) = blueprint_artifact_pair
      let inputs = expectation.inputs
      let params = blueprint.params

      case helpers.inputs_validator(params:, inputs:) {
        Ok(_) -> Error(Nil)
        Error(msg) -> Ok(msg)
      }
    })
    |> string.join(", ")

  use _ <- result.try(case input_validations_error {
    "" -> Ok(True)
    _ ->
      Error(helpers.JsonParserError(
        "Input validation errors: " <> input_validations_error,
      ))
  })

  use _ <- result.try(
    case
      helpers.validate_relevant_uniqueness(
        expectations,
        fn(e) { e.name },
        "expectation names",
      )
    {
      Ok(_) -> Ok(expectations)
      Error(err) -> Error(helpers.DuplicateError(err))
    },
  )

  // at this point we're completely validated
  let ir =
    expectations_blueprint_collection
    |> list.map(fn(expectation_and_blueprint_pair) {
      let #(expectation, blueprint) = expectation_and_blueprint_pair
      let value_tuples =
        expectation.inputs
        |> dict.keys
        |> list.map(fn(label) {
          // safe assertions since we're already validated everything
          let assert Ok(value) = expectation.inputs |> dict.get(label)
          let assert Ok(typ) = blueprint.params |> dict.get(label)

          middle_end.ValueTuple(label:, typ:, value:)
        })

      middle_end.IntermediateRepresentation(
        expectation_name: expectation.name,
        artifact_ref: blueprint.artifact_ref,
        values: value_tuples,
      )
    })

  Ok(ir)
}

fn bueprint_ref_decoder(blueprints: List(Blueprint)) {
  let artifact_names = blueprints |> list.map(fn(blueprint) { blueprint.name })

  decode.new_primitive_decoder("BlueprintReference", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) -> {
        case artifact_names |> list.contains(x) {
          True -> Ok(x)
          False -> Error("")
        }
      }
      _ -> Error("")
    }
  })
}

pub fn expectations_from_json(
  json_string: String,
  blueprints: List(Blueprint),
) -> Result(List(Expectation), json.DecodeError) {
  let expectation_decoded = {
    use name <- decode.field("name", decode.string)
    use blueprint_ref <- decode.field(
      "blueprint_ref",
      bueprint_ref_decoder(blueprints),
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
