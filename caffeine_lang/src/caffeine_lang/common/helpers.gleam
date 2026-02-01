import caffeine_lang/common/accepted_types
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string

/// A tuple of a label, type, and value used for template resolution.
pub type ValueTuple {
  ValueTuple(label: String, typ: accepted_types.AcceptedTypes, value: Dynamic)
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
      |> list.filter(fn(reference) {
        { reference |> reference_name } == { referrer |> referrer_reference }
      })
      |> list.first
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

/// Extract a value from a list of ValueTuple by label using the provided decoder.
pub fn extract_value(
  values: List(ValueTuple),
  label: String,
  decoder: decode.Decoder(a),
) -> Result(a, Nil) {
  values
  |> list.find(fn(vt) { vt.label == label })
  |> result.try(fn(vt) {
    decode.run(vt.value, decoder) |> result.replace_error(Nil)
  })
}

/// Extract the threshold from a list of values, falling back to the default.
pub fn extract_threshold(values: List(ValueTuple)) -> Float {
  extract_value(values, "threshold", decode.float)
  |> result.unwrap(default_threshold_percentage)
}

/// Extract dependency relations as a Dict of relation type to target list.
pub fn extract_relations(
  values: List(ValueTuple),
) -> dict.Dict(String, List(String)) {
  values
  |> list.find(fn(vt) { vt.label == "relations" })
  |> result.try(fn(vt) {
    decode.run(vt.value, decode.dict(decode.string, decode.list(decode.string)))
    |> result.replace_error(Nil)
  })
  |> result.unwrap(dict.new())
}
