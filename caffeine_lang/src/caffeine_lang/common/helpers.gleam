import caffeine_lang/common/accepted_types
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result

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
