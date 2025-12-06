import caffeine_lang_v2/common/helpers
import gleam/dict
import gleam/int
import gleam/list
import gleam/string

pub type Artifact {
  Artifact(
    name: String,
    version: Semver,
    base_params: dict.Dict(String, helpers.AcceptedTypes),
    params: dict.Dict(String, helpers.AcceptedTypes),
  )
}

pub opaque type Semver {
  Semver(major: Int, minor: Int, patch: Int)
}

pub fn make_semver(version version: String) -> Result(Semver, String) {
  case version |> string.split(".") |> list.try_map(int.parse) {
    Ok([major, minor, patch]) -> Ok(Semver(major:, minor:, patch:))
    _ ->
      Error(
        "Version must follow semantic versioning (X.Y.Z). See: https://semver.org/. Received '"
        <> version
        <> "'.",
      )
  }
}
