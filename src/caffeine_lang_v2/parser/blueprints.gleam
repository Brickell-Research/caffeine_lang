import caffeine_lang_v2/common/helpers
import gleam/dict

pub type Blueprint {
  Blueprint(
    name: String,
    artifact: String,
    params: dict.Dict(String, helpers.AcceptedTypes),
    inputs: dict.Dict(String, String),
  )
}
