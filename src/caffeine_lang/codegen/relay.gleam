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
////     Langfuse v2 metrics for `[from, to)` and submits one Datadog gauge per
////     scorer.
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
    /// Prefix for Datadog metric names. The relay emits
    /// `<metric_prefix>.count` (one gauge per scorer per window) and
    /// `<metric_prefix>.value` (one gauge per numeric scorer, avg value).
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
      content: workflow_yaml(relay),
    ),
    RelayFile(path: "relay/gleam.toml", content: runner_gleam_toml()),
    RelayFile(path: "relay/src/relay.gleam", content: runner_source(relay)),
  ]
}

fn workflow_yaml(relay: LangfuseDatadogRelay) -> String {
  // The default GITHUB_TOKEN cannot write repo Variables, so the cursor
  // steps use a PAT stored as `secrets.RELAY_PAT`. Required scopes:
  // `repo` (for classic PATs) or `Variables: read+write` (fine-grained).
  let cursor_var = cursor_var_name(relay)
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
    "",
    "      - name: Read cursor",
    "        id: cursor",
    "        env:",
    "          GH_TOKEN: ${{ secrets.RELAY_PAT }}",
    "        run: |",
    "          FROM=$(gh variable get " <> cursor_var
      <> " --repo \"$GITHUB_REPOSITORY\" 2>/dev/null || true)",
    "          if [ -z \"$FROM\" ]; then",
    "            FROM=$(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ)",
    "          fi",
    "          TO=$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "          echo \"from=$FROM\" >> \"$GITHUB_OUTPUT\"",
    "          echo \"to=$TO\" >> \"$GITHUB_OUTPUT\"",
    "",
    "      - name: Install deps",
    "        working-directory: relay",
    "        run: gleam deps download",
    "",
    "      - name: Run relay",
    "        working-directory: relay",
    "        env:",
    "          LANGFUSE_BASE_URL: ${{ vars.LANGFUSE_BASE_URL }}",
    "          LANGFUSE_PUBLIC_KEY: ${{ secrets.LANGFUSE_PUBLIC_KEY }}",
    "          LANGFUSE_SECRET_KEY: ${{ secrets.LANGFUSE_SECRET_KEY }}",
    "          DATADOG_API_KEY: ${{ secrets.DATADOG_API_KEY }}",
    "          LANGFUSE_FROM: ${{ steps.cursor.outputs.from }}",
    "          LANGFUSE_TO: ${{ steps.cursor.outputs.to }}",
    "        run: gleam run",
    "",
    "      - name: Advance cursor",
    "        if: success()",
    "        env:",
    "          GH_TOKEN: ${{ secrets.RELAY_PAT }}",
    "        run: |",
    "          gh variable set " <> cursor_var
      <> " --repo \"$GITHUB_REPOSITORY\" --body \"${{ steps.cursor.outputs.to }}\"",
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
    "langfuse_client = \">= 1.2.0 and < 2.0.0\"",
    "datadog_client = \">= 1.0.0 and < 2.0.0\"",
    "envoy = \">= 1.0.0 and < 2.0.0\"",
    "",
  ]
  |> string.join("\n")
}

fn runner_source(relay: LangfuseDatadogRelay) -> String {
  [
    "//// Relay runner: queries Langfuse v2 metrics for the window",
    "//// `[LANGFUSE_FROM, LANGFUSE_TO)` and submits one Datadog gauge per",
    "//// (scorer, data_type, score_source) row.",
    "",
    "import datadog_client",
    "import datadog_client/metric",
    "import envoy",
    "import gleam/int",
    "import gleam/io",
    "import gleam/list",
    "import langfuse_client/client",
    "import langfuse_client/metrics.{ScoresCategorical, ScoresNumeric}",
    "",
    "pub fn main() {",
    "  let assert Ok(langfuse_base) = envoy.get(\"LANGFUSE_BASE_URL\")",
    "  let assert Ok(langfuse_pk) = envoy.get(\"LANGFUSE_PUBLIC_KEY\")",
    "  let assert Ok(langfuse_sk) = envoy.get(\"LANGFUSE_SECRET_KEY\")",
    "  let assert Ok(dd_api_key) = envoy.get(\"DATADOG_API_KEY\")",
    "  let assert Ok(from_ts) = envoy.get(\"LANGFUSE_FROM\")",
    "  let assert Ok(to_ts) = envoy.get(\"LANGFUSE_TO\")",
    "",
    "  let lf =",
    "    client.new(",
    "      base_url: langfuse_base,",
    "      public_key: langfuse_pk,",
    "      secret_key: langfuse_sk,",
    "    )",
    "",
    "  let assert Ok(numeric_counts) =",
    "    metrics.list_score_counts(",
    "      lf,",
    "      metrics.score_count_query(",
    "        view: ScoresNumeric,",
    "        from: from_ts,",
    "        to: to_ts,",
    "      ),",
    "    )",
    "  let assert Ok(categorical_counts) =",
    "    metrics.list_score_counts(",
    "      lf,",
    "      metrics.score_count_query(",
    "        view: ScoresCategorical,",
    "        from: from_ts,",
    "        to: to_ts,",
    "      ),",
    "    )",
    "  let assert Ok(numeric_values) =",
    "    metrics.list_score_values(",
    "      lf,",
    "      metrics.score_value_query(from: from_ts, to: to_ts),",
    "    )",
    "",
    "  let count_rows = list.append(numeric_counts, categorical_counts)",
    "  let dd = datadog_client.new(dd_api_key)",
    "",
    "  list.each(count_rows, fn(row) {",
    "    let m =",
    "      metric.gauge(\"" <> relay.metric_prefix
      <> ".count\", int.to_float(row.count))",
    "      |> metric.with_tags(with: tags_for(row.name, row.data_type, row.source))",
    "    let assert Ok(_) = datadog_client.send_one(dd, m)",
    "  })",
    "",
    "  list.each(numeric_values, fn(row) {",
    "    let m =",
    "      metric.gauge(\"" <> relay.metric_prefix
      <> ".value\", row.avg_value)",
    "      |> metric.with_tags(with: tags_for(row.name, row.data_type, row.source))",
    "    let assert Ok(_) = datadog_client.send_one(dd, m)",
    "  })",
    "",
    "  io.println(",
    "    \"relayed \"",
    "    <> int.to_string(list.length(count_rows))",
    "    <> \" counts + \"",
    "    <> int.to_string(list.length(numeric_values))",
    "    <> \" values for [\"",
    "    <> from_ts",
    "    <> \", \"",
    "    <> to_ts",
    "    <> \")\",",
    "  )",
    "}",
    "",
    "fn tags_for(name: String, data_type: String, source: String) -> List(String) {",
    "  [",
    "    \"source:langfuse\",",
    "    \"relay:" <> relay.name <> "\",",
    "    \"scorer:\" <> name,",
    "    \"data_type:\" <> data_type,",
    "    \"score_source:\" <> source,",
    "  ]",
    "}",
    "",
  ]
  |> string.join("\n")
}

fn cursor_var_name(relay: LangfuseDatadogRelay) -> String {
  // GitHub Variables are uppercase alphanumeric + underscore. Uppercase the
  // relay name; the rest of the variable name documents intent.
  "RELAY_CURSOR_" <> string.uppercase(relay.name)
}
