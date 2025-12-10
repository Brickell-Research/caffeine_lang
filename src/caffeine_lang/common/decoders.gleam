import gleam/dynamic/decode
import gleam/list

/// Creates a decoder that validates a string is a valid reference to an item in a collection.
/// Returns the string if it matches a name in the collection, otherwise fails decoding.
pub fn named_reference_decoder(
  collection: List(a),
  name_extraction: fn(a) -> String,
) -> decode.Decoder(String) {
  let names = collection |> list.map(name_extraction)
  let default = Error("")

  decode.new_primitive_decoder("NamedReference", fn(dyn) {
    case decode.run(dyn, decode.string) {
      Ok(x) -> {
        case names |> list.contains(x) {
          True -> Ok(x)
          False -> default
        }
      }
      _ -> default
    }
  })
}
