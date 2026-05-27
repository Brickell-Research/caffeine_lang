//// Codegen for the Relay artifact.
////
//// A relay is a GitHub Action that pulls metrics from a source vendor and
//// pushes them to a destination vendor. The compiler emits a self-contained
//// set of files that a target repository drops in to start relaying.
////
//// Today the only supported pairing is Langfuse → Datadog, producing three
//// files:
////   - `.github/workflows/<name>.yml` — workflow that runs the runner on a
////     schedule, manages a cursor in a repo Variable, and dispatches manually.
////   - `relay/gleam.toml` — runner project manifest.
////   - `relay/src/relay.gleam` — runner that performs one relay tick: queries
////     Langfuse v2 metrics for `[from, to)` and submits one Datadog metric
////     per scorer.
////
//// File contents come from templates under `priv/templates/relay/<pairing>/`.
//// Each template is a real `.yml` / `.toml` / `.gleam` file with
//// `{{PLACEHOLDER}}` tokens — so editors and reviewers get the right syntax
//// highlighting and the diffs read naturally.

import gleam/list
import gleam/string
import simplifile

/// One file in a relay artifact's output: a path relative to the target
/// repository root, plus its full contents.
pub type RelayFile {
  RelayFile(path: String, content: String)
}

/// Configuration for a Langfuse → Datadog relay. These fields are the
/// placeholder shape until the language constructs land — at that point they
/// will be populated from a parsed relay declaration rather than constructed
/// directly.
pub type LangfuseDatadogRelay {
  LangfuseDatadogRelay(
    /// Identifier for the relay; used as the workflow filename stem and as
    /// the workflow's `name` field.
    name: String,
    /// Prefix for Datadog metric names — caller-supplied, no default. The
    /// relay emits `<metric_prefix>.count` (count metric, one submission per
    /// scorer per window) and `<metric_prefix>.value` (gauge, one submission
    /// per numeric scorer with the window's avg value). Choosing the prefix
    /// at relay-declaration time keeps the user's Datadog namespace under
    /// their own control.
    metric_prefix: String,
    /// Cron expression for the workflow's schedule trigger.
    schedule_cron: String,
  )
}

/// Generate the file set for a Langfuse → Datadog relay.
pub fn generate_langfuse_to_datadog(
  relay: LangfuseDatadogRelay,
) -> List(RelayFile) {
  [
    RelayFile(
      path: ".github/workflows/" <> relay.name <> ".yml",
      content: render(relay, "workflow.yml"),
    ),
    RelayFile(path: "relay/gleam.toml", content: render(relay, "gleam.toml")),
    RelayFile(
      path: "relay/src/relay.gleam",
      content: render(relay, "runner.gleam"),
    ),
  ]
}

const template_dir = "priv/templates/relay/langfuse_to_datadog/"

/// Read a template from `priv/templates/relay/langfuse_to_datadog/` and
/// substitute the relay's fields into the `{{PLACEHOLDER}}` tokens. A
/// missing template file means the package was shipped broken — assert so
/// it fails loudly.
fn render(relay: LangfuseDatadogRelay, template_name: String) -> String {
  let assert Ok(template) = simplifile.read(template_dir <> template_name)
  list.fold(substitutions(relay), template, fn(acc, sub) {
    let #(placeholder, value) = sub
    string.replace(acc, placeholder, value)
  })
}

fn substitutions(relay: LangfuseDatadogRelay) -> List(#(String, String)) {
  [
    #("{{RELAY_NAME}}", relay.name),
    #("{{METRIC_PREFIX}}", relay.metric_prefix),
    #("{{SCHEDULE_CRON}}", relay.schedule_cron),
    #("{{CURSOR_VAR}}", cursor_var_name(relay)),
  ]
}

fn cursor_var_name(relay: LangfuseDatadogRelay) -> String {
  // GitHub Variables are uppercase alphanumeric + underscore. Uppercase the
  // relay name; the rest of the variable name documents intent.
  "RELAY_CURSOR_" <> string.uppercase(relay.name)
}
