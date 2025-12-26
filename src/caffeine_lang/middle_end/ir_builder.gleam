import caffeine_lang/common/accepted_types.{Defaulted, ModifierType, Optional}
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer.{
  type IntermediateRepresentation,
}
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations.{type Expectation}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option
import gleam/string

/// Build intermediate representations from validated expectations across multiple files.
pub fn build_all(
  expectations_with_paths: List(#(List(#(Expectation, Blueprint)), String)),
) -> List(IntermediateRepresentation) {
  expectations_with_paths
  |> list.map(fn(pair) {
    let #(expectations_blueprint_collection, file_path) = pair
    build(expectations_blueprint_collection, file_path)
  })
  |> list.flatten
}

/// Build intermediate representations from validated expectations for a single file.
fn build(
  expectations_blueprint_collection: List(#(Expectation, Blueprint)),
  file_path: String,
) -> List(IntermediateRepresentation) {
  expectations_blueprint_collection
  |> list.map(fn(expectation_and_blueprint_pair) {
    let #(expectation, blueprint) = expectation_and_blueprint_pair

    // merge blueprint inputs with expectation inputs
    // Expectation inputs override blueprint inputs for the same key
    let merged_inputs = dict.merge(blueprint.inputs, expectation.inputs)

    // Build value tuples from provided inputs
    let provided_value_tuples =
      merged_inputs
      |> dict.keys
      |> list.map(fn(label) {
        // safe assertions since we're already validated everything
        let assert Ok(value) = merged_inputs |> dict.get(label)
        let assert Ok(typ) = blueprint.params |> dict.get(label)

        helpers.ValueTuple(label:, typ:, value:)
      })

    // Also include Optional and Defaulted params that weren't provided
    // These need to be in value_tuples so the templatizer can resolve them
    let unprovided_optional_value_tuples =
      blueprint.params
      |> dict.to_list
      |> list.filter_map(fn(param) {
        let #(label, typ) = param
        case dict.has_key(merged_inputs, label) {
          True -> Error(Nil)
          False ->
            case typ {
              ModifierType(Optional(_)) | ModifierType(Defaulted(_, _)) ->
                Ok(helpers.ValueTuple(label:, typ:, value: dynamic.nil()))
              _ -> Error(Nil)
            }
        }
      })

    let value_tuples =
      list.append(provided_value_tuples, unprovided_optional_value_tuples)

    let misc_metadata =
      value_tuples
      |> list.filter_map(fn(value_tuple) {
        // safe assertion since we're already validated everything
        case value_tuple.label, decode.run(value_tuple.value, decode.string) {
          // for some reason we cannot parse the value
          _, Error(_) -> Error(Nil)
          // TODO: make the tag filtering dynamic
          "window_in_days", _ | "threshold", _ | "value", _ -> Error(Nil)
          _, Ok(value_string) -> Ok(#(value_tuple.label, value_string))
        }
      })
      |> dict.from_list

    // build unique expectation name by combining path prefix with name
    let #(org, team, service) = extract_path_prefix(file_path)
    let service_name = service
    let unique_name = org <> "_" <> service_name <> "_" <> expectation.name

    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: expectation.name,
        org_name: org,
        service_name: service_name,
        blueprint_name: blueprint.name,
        team_name: team,
        misc: misc_metadata,
      ),
      unique_identifier: unique_name,
      artifact_ref: blueprint.artifact_ref,
      values: value_tuples,
      vendor: option.None,
    )
  })
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
    // this is not actually a possible state, however for pattern matching completeness we
    // inlcude it here
    _ -> #("unknown", "unknown", "unknown")
  }
}
