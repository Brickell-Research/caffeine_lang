import caffeine_lang/constants
import caffeine_lang/identifiers.{
  type ExpectationLabel, type MeasurementName, type OrgName, type ServiceName,
  type TeamName,
}
import caffeine_lang/linker/artifacts.{type DependencyRelationType}
import caffeine_lang/types
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

/// A tuple of a label, type, and value used for template resolution.
pub type ValueTuple {
  ValueTuple(label: String, typ: types.AcceptedTypes, value: Value)
}

/// Maps each referrer to its corresponding reference by matching names.
/// Returns a list of tuples pairing each referrer with its matched reference.
@internal
pub fn map_reference_to_referrer_over_collection(
  references references: List(a),
  referrers referrers: List(b),
  reference_name reference_name: fn(a) -> String,
  referrer_reference referrer_reference: fn(b) -> String,
) {
  let reference_map =
    references
    |> list.map(fn(ref) { #(reference_name(ref), ref) })
    |> dict.from_list

  referrers
  |> list.filter_map(fn(referrer) {
    dict.get(reference_map, referrer_reference(referrer))
    |> result.map(fn(reference) { #(referrer, reference) })
  })
}

/// Extract a meaningful prefix from the source path.
/// e.g., "examples/org/platform_team/authentication.caffeine" -> #("org", "platform_team", "authentication")
@internal
pub fn extract_path_prefix(path: String) -> #(String, String, String) {
  case
    path
    |> string.split("/")
    |> list.reverse
    |> list.take(3)
    |> list.reverse
    |> list.map(fn(segment) {
      // Remove file extension if present.
      case string.ends_with(segment, ".caffeine") {
        True -> string.drop_end(segment, 9)
        False ->
          case string.ends_with(segment, ".json") {
            True -> string.drop_end(segment, 5)
            False -> segment
          }
      }
    })
  {
    [org, team, service] -> #(org, team, service)
    // This is not actually a possible state, however for pattern matching completeness we
    // include it here.
    _ -> #("unknown", "unknown", "unknown")
  }
}

/// Default SLO threshold percentage used when no explicit threshold is provided.
pub const default_threshold_percentage = 99.9

/// Default SLO window in days used when no explicit window is provided.
pub const default_window_in_days = 30

/// Build a Dict index from a list of ValueTuples for O(1) label lookups.
@internal
pub fn index_value_tuples(
  values: List(ValueTuple),
) -> dict.Dict(String, ValueTuple) {
  values
  |> list.map(fn(vt) { #(vt.label, vt) })
  |> dict.from_list
}

/// Extract a value from an indexed Dict of ValueTuples by label.
@internal
pub fn extract_value(
  index: dict.Dict(String, ValueTuple),
  label: String,
  extractor: fn(Value) -> Result(a, Nil),
) -> Result(a, Nil) {
  index
  |> dict.get(label)
  |> result.try(fn(vt) { extractor(vt.value) })
}

/// Extract dependency relations from an indexed Dict of ValueTuples.
@internal
pub fn extract_depends_on(
  index: dict.Dict(String, ValueTuple),
) -> dict.Dict(DependencyRelationType, List(String)) {
  index
  |> dict.get("depends_on")
  |> extract_relations_from_value_tuple
}

/// Shared implementation for extracting relations from a Result(ValueTuple, Nil).
fn extract_relations_from_value_tuple(
  vt_result: Result(ValueTuple, Nil),
) -> dict.Dict(DependencyRelationType, List(String)) {
  vt_result
  |> result.try(fn(vt) {
    case vt.value {
      value.DictValue(d) ->
        d
        |> dict.to_list
        |> list.try_map(fn(pair) {
          case pair.1 {
            value.ListValue(items) -> {
              items
              |> list.try_map(value.extract_string)
              |> result.map(fn(strings) { #(pair.0, strings) })
            }
            _ -> Error(Nil)
          }
        })
        |> result.map(fn(pairs) {
          pairs
          |> list.filter_map(fn(pair) {
            case artifacts.parse_relation_type(pair.0) {
              Ok(rt) -> Ok(#(rt, pair.1))
              Error(Nil) -> Error(Nil)
            }
          })
          |> dict.from_list
        })
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(dict.new())
}

/// Extract the window_in_days from an indexed Dict, falling back to the default.
@internal
pub fn extract_window_in_days(
  index: dict.Dict(String, ValueTuple),
) -> Int {
  extract_value(index, "window_in_days", value.extract_int)
  |> result.unwrap(default_window_in_days)
}

/// Extract indicators from an indexed Dict of ValueTuples.
@internal
pub fn extract_indicators(
  index: dict.Dict(String, ValueTuple),
) -> dict.Dict(String, String) {
  index
  |> dict.get("indicators")
  |> result.try(fn(vt) { value.extract_string_dict(vt.value) })
  |> result.unwrap(dict.new())
}

/// Extract user-provided tags from an indexed Dict of ValueTuples.
@internal
pub fn extract_tags(
  index: dict.Dict(String, ValueTuple),
) -> List(#(String, String)) {
  index
  |> dict.get("tags")
  |> result.try(fn(vt) {
    case vt.value {
      value.NilValue -> Ok(dict.new())
      value.DictValue(_) -> value.extract_string_dict(vt.value)
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(dict.new())
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

/// Build system tag key-value pairs from IR metadata fields.
/// Returns a sorted, deterministic list of tag pairs shared across all generators.
pub fn build_system_tag_pairs(
  org_name org_name: OrgName,
  team_name team_name: TeamName,
  service_name service_name: ServiceName,
  measurement_name measurement_name: MeasurementName,
  friendly_label friendly_label: ExpectationLabel,
  misc misc: dict.Dict(String, List(String)),
) -> List(#(String, String)) {
  [
    #("managed_by", "caffeine"),
    #("caffeine_version", constants.version),
    #("org", org_name.value),
    #("team", team_name.value),
    #("service", service_name.value),
    #("measurement", measurement_name.value),
    #("expectation", friendly_label.value),
  ]
  |> list.append(
    misc
    |> dict.to_list
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.flat_map(fn(pair) {
      let #(key, values) = pair
      values
      |> list.sort(string.compare)
      |> list.map(fn(value) { #(key, value) })
    }),
  )
}
