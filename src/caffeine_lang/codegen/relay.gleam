//// Codegen for the Relay artifact.
////
//// A relay is a GitHub Action that pulls metrics from a source vendor and
//// pushes them to a destination vendor. The compiler emits a self-contained
//// set of files that a target repository drops in to start relaying.
////
//// Today the only supported pairing is Langfuse → Datadog, producing three
//// files:
////   - `.github/workflows/<name>.yml` — workflow that runs the runner on a
////     schedule and on manual dispatch.
////   - `relay/gleam.toml` — runner project manifest pulling in
////     `langfuse_client` and `datadog_client`.
////   - `relay/src/relay.gleam` — runner that performs one relay tick.
////
//// The module is intentionally pure (string in, strings out) so the language
//// constructs that will eventually drive it can be wired in without changing
//// the output shape.

import gleam/string

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
    /// Datadog metric name the relay submits (e.g. `"langfuse.scores.count"`).
    metric_name: String,
    /// Cron expression for the workflow's schedule trigger.
    schedule_cron: String,
  )
}

/// Generate the file set for a Langfuse → Datadog relay.
pub fn generate_langfuse_to_datadog(relay: LangfuseDatadogRelay) -> List(RelayFile) {
  [
    RelayFile(
      path: ".github/workflows/" <> relay.name <> ".yml",
      content: workflow_yaml(relay),
    ),
    RelayFile(path: "relay/gleam.toml", content: runner_gleam_toml()),
    RelayFile(path: "relay/src/relay.gleam", content: runner_source(relay)),
  ]
}

fn workflow_yaml(relay: LangfuseDatadogRelay) -> String {
  [
    "name: " <> relay.name,
    "",
    "on:",
    "  schedule:",
    "    - cron: '" <> relay.schedule_cron <> "'",
    "  workflow_dispatch:",
    "",
    "jobs:",
    "  relay:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - uses: actions/checkout@v4",
    "      - uses: erlef/setup-beam@v1",
    "        with:",
    "          otp-version: \"27\"",
    "          gleam-version: \"1.6.0\"",
    "      - name: Install deps",
    "        working-directory: relay",
    "        run: gleam deps download",
    "      - name: Run relay",
    "        working-directory: relay",
    "        env:",
    "          LANGFUSE_BASE_URL: ${{ vars.LANGFUSE_BASE_URL }}",
    "          LANGFUSE_PUBLIC_KEY: ${{ secrets.LANGFUSE_PUBLIC_KEY }}",
    "          LANGFUSE_SECRET_KEY: ${{ secrets.LANGFUSE_SECRET_KEY }}",
    "          DATADOG_API_KEY: ${{ secrets.DATADOG_API_KEY }}",
    "        run: gleam run",
    "",
  ]
  |> string.join("\n")
}

fn runner_gleam_toml() -> String {
  [
    "name = \"relay\"",
    "version = \"0.1.0\"",
    "target = \"erlang\"",
    "",
    "[dependencies]",
    "gleam_stdlib = \">= 0.40.0 and < 2.0.0\"",
    "langfuse_client = \">= 1.0.0 and < 2.0.0\"",
    "datadog_client = \">= 1.0.0 and < 2.0.0\"",
    "envoy = \">= 1.0.0 and < 2.0.0\"",
    "",
  ]
  |> string.join("\n")
}

fn runner_source(relay: LangfuseDatadogRelay) -> String {
  [
    "import datadog_client",
    "import datadog_client/metric",
    "import envoy",
    "import gleam/int",
    "import gleam/io",
    "import langfuse_client/client",
    "import langfuse_client/score",
    "",
    "pub fn main() {",
    "  let assert Ok(langfuse_base) = envoy.get(\"LANGFUSE_BASE_URL\")",
    "  let assert Ok(langfuse_pk) = envoy.get(\"LANGFUSE_PUBLIC_KEY\")",
    "  let assert Ok(langfuse_sk) = envoy.get(\"LANGFUSE_SECRET_KEY\")",
    "  let assert Ok(dd_api_key) = envoy.get(\"DATADOG_API_KEY\")",
    "",
    "  let lf =",
    "    client.new(",
    "      base_url: langfuse_base,",
    "      public_key: langfuse_pk,",
    "      secret_key: langfuse_sk,",
    "    )",
    "",
    // limit:1 keeps the response tiny — total_items is server-side and
    // independent of the page size.
    "  let assert Ok(scores) =",
    "    score.list(lf, score.query() |> score.with_limit(1))",
    "  let count = scores.meta.total_items",
    "",
    "  let dd = datadog_client.new(dd_api_key)",
    "  let m =",
    "    metric.gauge(\"" <> relay.metric_name <> "\", int.to_float(count))",
    "    |> metric.with_tags(with: [\"source:langfuse\"])",
    "",
    "  let assert Ok(_) = datadog_client.send_one(dd, m)",
    "  io.println(",
    "    \"relayed " <> relay.metric_name <> "=\" <> int.to_string(count),",
    "  )",
    "}",
    "",
  ]
  |> string.join("\n")
}
