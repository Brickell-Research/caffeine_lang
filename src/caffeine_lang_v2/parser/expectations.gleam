import gleam/dict

pub type Expectation {
  Expectation(
    name: String,
    blueprint: String,
    inputs: dict.Dict(String, String),
  )
}
