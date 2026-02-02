import caffeine_lang/constants
import caffeine_lang/linker/artifacts.{type ArtifactType}
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
  referrers
  |> list.map(fn(referrer) {
    // Already performed this check so can assert it.
    let assert Ok(reference) =
      references
      |> list.find(fn(reference) {
        { reference |> reference_name } == { referrer |> referrer_reference }
      })
    #(referrer, reference)
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

/// Extract a value from a list of ValueTuple by label using the provided extractor.
pub fn extract_value(
  values: List(ValueTuple),
  label: String,
  extractor: fn(Value) -> Result(a, Nil),
) -> Result(a, Nil) {
  values
  |> list.find(fn(vt) { vt.label == label })
  |> result.try(fn(vt) { extractor(vt.value) })
}

/// Extract the threshold from a list of values, falling back to the default.
pub fn extract_threshold(values: List(ValueTuple)) -> Float {
  extract_value(values, "threshold", value.extract_float)
  |> result.unwrap(default_threshold_percentage)
}

/// Extract dependency relations as a Dict of relation type to target list.
pub fn extract_relations(
  values: List(ValueTuple),
) -> dict.Dict(String, List(String)) {
  values
  |> list.find(fn(vt) { vt.label == "relations" })
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
        |> result.map(dict.from_list)
      _ -> Error(Nil)
    }
  })
  |> result.unwrap(dict.new())
}

/// Default SLO window in days used when no explicit window is provided.
pub const default_window_in_days = 30

/// Extract the window_in_days from a list of values, falling back to the default.
pub fn extract_window_in_days(values: List(ValueTuple)) -> Int {
  extract_value(values, "window_in_days", value.extract_int)
  |> result.unwrap(default_window_in_days)
}

/// Extract indicators from a list of values as a Dict mapping indicator names to expressions.
pub fn extract_indicators(values: List(ValueTuple)) -> dict.Dict(String, String) {
  values
  |> list.find(fn(vt) { vt.label == "indicators" })
  |> result.try(fn(vt) { value.extract_string_dict(vt.value) })
  |> result.unwrap(dict.new())
}

/// Extract user-provided tags as a sorted list of key-value pairs.
pub fn extract_tags(values: List(ValueTuple)) -> List(#(String, String)) {
  values
  |> list.find(fn(vt) { vt.label == "tags" })
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

/// Build system tag key-value pairs from IR metadata fields and artifact refs.
/// Returns a sorted, deterministic list of tag pairs shared across all generators.
pub fn build_system_tag_pairs(
  org_name org_name: String,
  team_name team_name: String,
  service_name service_name: String,
  blueprint_name blueprint_name: String,
  friendly_label friendly_label: String,
  artifact_refs artifact_refs: List(ArtifactType),
  misc misc: dict.Dict(String, List(String)),
) -> List(#(String, String)) {
  [
    #("managed_by", "caffeine"),
    #("caffeine_version", constants.version),
    #("org", org_name),
    #("team", team_name),
    #("service", service_name),
    #("blueprint", blueprint_name),
    #("expectation", friendly_label),
  ]
  |> list.append(
    artifact_refs
    |> list.map(fn(ref) {
      #("artifact", artifacts.artifact_type_to_string(ref))
    }),
  )
  |> list.append(
    misc
    |> dict.keys
    |> list.sort(string.compare)
    |> list.flat_map(fn(key) {
      let assert Ok(values) = misc |> dict.get(key)
      values
      |> list.sort(string.compare)
      |> list.map(fn(value) { #(key, value) })
    }),
  )
}
