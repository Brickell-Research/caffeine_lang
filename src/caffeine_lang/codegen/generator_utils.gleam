import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{type IntermediateRepresentationMetaData}
import gleam/list
import gleam/option
import gleam/string
import terra_madre/render
import terra_madre/terraform.{
  type Provider, type Resource, type TerraformSettings, type Variable,
}

/// Rewrite a string so it's safe to use as a fragment of a Datadog metric
/// name. Datadog metric names must be `[A-Za-z0-9._]` — anything else
/// (notably whitespace) gets converted to underscores by DD at submission,
/// which silently misroutes data because the submitted name no longer
/// matches the SLO query. We force the conversion at codegen time so the
/// emitted metric, the relay's submission target, and the SLO's query are
/// all the same string by construction.
///
/// `caffeine_lang`'s expectation / measurement names allow spaces (e.g.
/// `"My First SLO"`); those names flow into `ir.unique_identifier` and
/// must be sanitized before use in a metric query.
@internal
pub fn dd_metric_safe(s: String) -> String {
  s
  |> string.to_graphemes
  |> list.map(fn(g) {
    case is_dd_metric_char(g) {
      True -> g
      False -> "_"
    }
  })
  |> string.concat
}

fn is_dd_metric_char(g: String) -> Bool {
  case g {
    "." | "_" -> True
    _ ->
      case string.to_utf_codepoints(g) {
        [cp] -> {
          let n = string.utf_codepoint_to_int(cp)
          // 0-9: 48-57, A-Z: 65-90, a-z: 97-122.
          { n >= 48 && n <= 57 }
          || { n >= 65 && n <= 90 }
          || { n >= 97 && n <= 122 }
        }
        _ -> False
      }
  }
}

/// Drop the last `n` UTF-16 codeunits. `string.drop_end` walks the entire
/// rendered Terraform via Intl.Segmenter to count graphemes from the end —
/// pure overhead for an ASCII trailing newline, and called once per resource
/// (~600× on the huge corpus, where it was the largest residual grapheme cost).
@external(erlang, "codegen_ffi", "drop_end_codeunits")
@external(javascript, "./codegen_ffi.mjs", "drop_end_codeunits")
fn drop_end_codeunits(s: String, n: Int) -> String

/// Render a Terraform config from resources, settings, providers, and variables.
/// Assembles the standard Config structure and renders it to HCL.
@internal
pub fn render_terraform_config(
  resources resources: List(Resource),
  settings settings: TerraformSettings,
  providers providers: List(Provider),
  variables variables: List(Variable),
) -> String {
  let config =
    terraform.Config(
      terraform: option.Some(settings),
      providers: providers,
      resources: resources,
      data_sources: [],
      variables: variables,
      outputs: [],
      locals: [],
      modules: [],
    )
  render.render_config(config)
}

/// Build an HCL comment identifying the source measurement and expectation.
@internal
pub fn build_source_comment(
  metadata: IntermediateRepresentationMetaData,
) -> String {
  "# Caffeine: "
  <> metadata.org_name.value
  <> "."
  <> metadata.team_name.value
  <> "."
  <> metadata.service_name.value
  <> "."
  <> metadata.friendly_label.value
  <> " (measurement: "
  <> metadata.measurement_name.value
  <> ")"
}

/// Render a single Terraform resource to HCL string (no trailing newline).
@internal
pub fn render_resource_to_string(resource: Resource) -> String {
  let config =
    terraform.Config(
      terraform: option.None,
      providers: [],
      resources: [resource],
      data_sources: [],
      variables: [],
      outputs: [],
      locals: [],
      modules: [],
    )
  render.render_config(config)
  |> drop_end_codeunits(1)
}

/// Build a codegen resolution error with empty context.
@internal
pub fn resolution_error(
  vendor vendor_name: String,
  msg msg: String,
) -> CompilationError {
  errors.generator_terraform_resolution_error(vendor: vendor_name, msg:)
}
