//// Relay runner: queries Langfuse v2 metrics for the window
//// `[LANGFUSE_FROM, LANGFUSE_TO)` and submits one Datadog metric per
//// (scorer, data_type, score_source) row. The scorer allowlist comes from
//// `manifest.scorers()` and is passed to Langfuse as a server-side filter,
//// so we only pay for the data we actually use.

import datadog_client
import datadog_client/metric
import envoy
import gleam/int
import gleam/io
import gleam/list
import langfuse_client/client
import langfuse_client/metrics.{ScoresCategorical, ScoresNumeric}
import manifest

pub fn main() {
  let assert Ok(langfuse_base) = envoy.get("LANGFUSE_BASE_URL")
  let assert Ok(langfuse_pk) = envoy.get("LANGFUSE_PUBLIC_KEY")
  let assert Ok(langfuse_sk) = envoy.get("LANGFUSE_SECRET_KEY")
  let assert Ok(dd_api_key) = envoy.get("DATADOG_API_KEY")
  let assert Ok(from_ts) = envoy.get("LANGFUSE_FROM")
  let assert Ok(to_ts) = envoy.get("LANGFUSE_TO")

  let lf =
    client.new(
      base_url: langfuse_base,
      public_key: langfuse_pk,
      secret_key: langfuse_sk,
    )

  let filters = [
    metrics.scorer_names(list.map(manifest.scorers(), fn(s) { s.name })),
  ]

  let assert Ok(numeric_counts) =
    metrics.list_score_counts(
      lf,
      metrics.score_count_query(
        view: ScoresNumeric,
        from: from_ts,
        to: to_ts,
        filters: filters,
      ),
    )
  let assert Ok(categorical_counts) =
    metrics.list_score_counts(
      lf,
      metrics.score_count_query(
        view: ScoresCategorical,
        from: from_ts,
        to: to_ts,
        filters: filters,
      ),
    )
  let assert Ok(numeric_values) =
    metrics.list_score_values(
      lf,
      metrics.score_value_query(
        from: from_ts,
        to: to_ts,
        filters: filters,
      ),
    )

  let count_rows = list.append(numeric_counts, categorical_counts)
  let dd = datadog_client.new(dd_api_key)

  list.each(count_rows, fn(row) {
    let m =
      metric.count(
        manifest.metric_prefix <> ".count",
        int.to_float(row.count),
      )
      |> metric.with_tags(with: tags_for(row.name, row.data_type, row.source))
    let assert Ok(_) = datadog_client.send_one(dd, m)
  })

  list.each(numeric_values, fn(row) {
    let m =
      metric.gauge(manifest.metric_prefix <> ".value", row.avg_value)
      |> metric.with_tags(with: tags_for(row.name, row.data_type, row.source))
    let assert Ok(_) = datadog_client.send_one(dd, m)
  })

  io.println(
    "relayed "
    <> int.to_string(list.length(count_rows))
    <> " counts + "
    <> int.to_string(list.length(numeric_values))
    <> " values for ["
    <> from_ts
    <> ", "
    <> to_ts
    <> ")",
  )
}

fn tags_for(name: String, data_type: String, source: String) -> List(String) {
  [
    "source:langfuse",
    "relay:" <> manifest.relay_name,
    "scorer:" <> name,
    "data_type:" <> data_type,
    "score_source:" <> source,
  ]
}
