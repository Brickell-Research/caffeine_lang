/// Codegen for the bundled relay Gleam project.
import gleam/dict.{type Dict}
import gleam/option.{type Option}

@internal
pub fn generate() -> Option(Dict(String, String)) {
  option.Some(
    dict.from_list([
      #("gleam.toml", relay_gleam_toml),
      #("src/caffeine_relay.gleam", relay_src),
      #(".gitignore", relay_gitignore),
    ]),
  )
}

const relay_gleam_toml = "name = \"caffeine_relay\"
version = \"0.0.0\"
target = \"erlang\"

[dependencies]
gleam_stdlib = \">= 1.0.0 and < 2.0.0\"
gleam_json = \">= 3.0.0 and < 4.0.0\"
gleam_http = \">= 4.0.0 and < 5.0.0\"
gleam_httpc = \">= 5.0.0 and < 6.0.0\"
simplifile = \">= 2.0.0 and < 3.0.0\"
argv = \">= 1.0.0 and < 2.0.0\"
envoy = \">= 1.0.0 and < 2.0.0\"
"

const relay_src = "
//// Caffeine relay — Langfuse score → Datadog metric forwarder.
////
//// Auto-vended by `caffeine_lang`. Do not hand-edit; rerun
//// `caffeine compile` to regenerate.

import argv
import envoy
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/http.{Post}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

// ===========================================================================
// Types
// ===========================================================================

pub type Config {
  Config(signals: List(SignalEntry))
}

pub type SignalEntry {
  SignalEntry(
    metric: String,
    kind: String,
    source: String,
    match: dict.Dict(String, String),
    tags: dict.Dict(String, String),
    value_path: Option(String),
  )
}

pub type Cursor {
  Cursor(langfuse_since: Option(String))
}

pub type LangfuseScore {
  LangfuseScore(
    name: String,
    string_value: Option(String),
    timestamp: String,
  )
}

pub type LangfuseCredentials {
  LangfuseCredentials(
    public_key: String,
    secret_key: String,
    base_url: String,
  )
}

pub type DatadogPoint {
  DatadogPoint(
    metric: String,
    value: Float,
    timestamp: Int,
    tags: dict.Dict(String, String),
  )
}

/// Self-observability counters accumulated over a single relay run. Emitted
/// at the end of every run (success or failure) as `caffeine.relay.*`
/// metrics so operators can alert on relay health independently of the
/// signals it forwards.
pub type RunStats {
  RunStats(
    scores_processed: Int,
    metric_points_emitted: Int,
    failure_phase: Option(String),
  )
}

fn empty_stats() -> RunStats {
  RunStats(
    scores_processed: 0,
    metric_points_emitted: 0,
    failure_phase: None,
  )
}

// ===========================================================================
// Entry point
// ===========================================================================

pub fn main() -> Nil {
  let start = now_unix()
  // Load the DD API key up front: without it we can't emit self-observability
  // metrics, so there's no point continuing.
  case load_dd_api_key() {
    Error(msg) -> {
      io.println_error(\"caffeine-relay error: \" <> msg)
      panic as msg
    }
    Ok(dd_key) -> {
      let #(stats, outcome) = run_with_stats(dd_key)
      // Always emit self-metrics — success or failure. If this submission
      // itself fails (e.g. DD outage is the root cause) the GHA cron log is
      // the fallback signal. Ignore the result; we're already exiting.
      let _ = emit_self_metrics(dd_key, stats, start)
      case outcome {
        Ok(summary) -> io.println(summary)
        Error(msg) -> {
          io.println_error(\"caffeine-relay error: \" <> msg)
          panic as msg
        }
      }
    }
  }
}

fn run_with_stats(dd_key: String) -> #(RunStats, Result(String, String)) {
  let args = argv.load().arguments
  case parse_args(args) {
    Error(msg) -> #(failure_stats(\"parse\"), Error(msg))
    Ok(#(config_path, cursor_path)) ->
      case load_config(config_path) {
        Error(msg) -> #(failure_stats(\"parse\"), Error(msg))
        Ok(config) ->
          case load_cursor(cursor_path) {
            Error(msg) -> #(failure_stats(\"cursor_io\"), Error(msg))
            Ok(cursor) ->
              run_pipeline(config, cursor, cursor_path, dd_key)
          }
      }
  }
}

fn run_pipeline(
  config: Config,
  cursor: Cursor,
  cursor_path: String,
  dd_key: String,
) -> #(RunStats, Result(String, String)) {
  let langfuse_signals =
    list.filter(config.signals, fn(s) { s.source == \"langfuse\" })
  case langfuse_signals {
    [] -> #(
      empty_stats(),
      Ok(\"caffeine-relay: no langfuse signals to route, skipping\"),
    )
    _ ->
      case load_langfuse_credentials() {
        Error(msg) -> #(failure_stats(\"parse\"), Error(msg))
        Ok(lf_creds) ->
          case fetch_langfuse_scores(lf_creds, cursor.langfuse_since) {
            Error(msg) -> #(failure_stats(\"langfuse_fetch\"), Error(msg))
            Ok(scores) -> {
              let points = dispatch_scores(scores, langfuse_signals)
              let scores_n = list.length(scores)
              let points_n = list.length(points)
              case submit_to_datadog(dd_key, points) {
                Error(msg) -> #(
                  RunStats(
                    scores_processed: scores_n,
                    metric_points_emitted: 0,
                    failure_phase: Some(\"dd_submit\"),
                  ),
                  Error(msg),
                )
                Ok(_) -> {
                  let new_cursor = cursor_after(cursor, scores)
                  case save_cursor(cursor_path, new_cursor) {
                    Error(msg) -> #(
                      RunStats(
                        scores_processed: scores_n,
                        metric_points_emitted: points_n,
                        failure_phase: Some(\"cursor_io\"),
                      ),
                      Error(msg),
                    )
                    Ok(_) -> #(
                      RunStats(
                        scores_processed: scores_n,
                        metric_points_emitted: points_n,
                        failure_phase: None,
                      ),
                      Ok(
                        \"caffeine-relay: processed \"
                        <> int.to_string(scores_n)
                        <> \" scores, emitted \"
                        <> int.to_string(points_n)
                        <> \" metric points\",
                      ),
                    )
                  }
                }
              }
            }
          }
      }
  }
}

fn failure_stats(phase: String) -> RunStats {
  RunStats(
    scores_processed: 0,
    metric_points_emitted: 0,
    failure_phase: Some(phase),
  )
}

// ===========================================================================
// Argument parsing
// ===========================================================================

fn parse_args(args: List(String)) -> Result(#(String, String), String) {
  parse_args_loop(args, None, None)
}

fn parse_args_loop(
  args: List(String),
  config: Option(String),
  cursor: Option(String),
) -> Result(#(String, String), String) {
  case args {
    [] ->
      case config, cursor {
        Some(c), Some(cu) -> Ok(#(c, cu))
        None, _ -> Error(\"--config <path> is required\")
        _, None -> Error(\"--cursor <path> is required\")
      }
    [\"--config\", path, ..rest] -> parse_args_loop(rest, Some(path), cursor)
    [\"--cursor\", path, ..rest] -> parse_args_loop(rest, config, Some(path))
    [unknown, ..] -> Error(\"unknown argument: \" <> unknown)
  }
}

// ===========================================================================
// Config (signals.json) parsing
// ===========================================================================

fn load_config(path: String) -> Result(Config, String) {
  use text <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { \"failed to read config: \" <> path }),
  )
  json.parse(text, config_decoder())
  |> result.map_error(fn(err) {
    \"failed to parse config: \" <> string.inspect(err)
  })
}

fn config_decoder() -> decode.Decoder(Config) {
  use signals <- decode.field(\"signals\", decode.list(signal_entry_decoder()))
  decode.success(Config(signals: signals))
}

fn signal_entry_decoder() -> decode.Decoder(SignalEntry) {
  use metric <- decode.field(\"metric\", decode.string)
  use kind <- decode.field(\"kind\", decode.string)
  use source <- decode.field(\"source\", decode.string)
  use match <- decode.field(
    \"match\",
    decode.dict(decode.string, decode.string),
  )
  use tags <- decode.field(
    \"tags\",
    decode.dict(decode.string, decode.string),
  )
  use value_path <- decode.field(
    \"value_path\",
    decode.optional(decode.string),
  )
  decode.success(SignalEntry(
    metric: metric,
    kind: kind,
    source: source,
    match: match,
    tags: tags,
    value_path: value_path,
  ))
}

// ===========================================================================
// Cursor I/O
// ===========================================================================

fn load_cursor(path: String) -> Result(Cursor, String) {
  case simplifile.read(path) {
    Error(_) -> Ok(Cursor(langfuse_since: None))
    Ok(text) ->
      json.parse(text, cursor_decoder())
      |> result.map_error(fn(err) {
        \"failed to parse cursor: \" <> string.inspect(err)
      })
  }
}

fn cursor_decoder() -> decode.Decoder(Cursor) {
  use since <- decode.field(\"langfuse_since\", decode.optional(decode.string))
  decode.success(Cursor(langfuse_since: since))
}

fn save_cursor(path: String, cursor: Cursor) -> Result(Nil, String) {
  let body =
    json.to_string(
      json.object([
        #(\"langfuse_since\", case cursor.langfuse_since {
          None -> json.null()
          Some(s) -> json.string(s)
        }),
      ]),
    )
  simplifile.write(path, body)
  |> result.map_error(fn(_) { \"failed to write cursor: \" <> path })
}

fn cursor_after(prev: Cursor, scores: List(LangfuseScore)) -> Cursor {
  case scores {
    [] -> prev
    _ -> {
      let latest =
        scores
        |> list.map(fn(s) { s.timestamp })
        |> list.sort(string.compare)
        |> list.last
      case latest {
        Ok(ts) -> Cursor(langfuse_since: Some(ts))
        Error(_) -> prev
      }
    }
  }
}

// ===========================================================================
// Langfuse client
// ===========================================================================

fn load_langfuse_credentials() -> Result(LangfuseCredentials, String) {
  use public_key <- result.try(
    envoy.get(\"LANGFUSE_PUBLIC_KEY\")
    |> result.replace_error(\"LANGFUSE_PUBLIC_KEY not set\"),
  )
  use secret_key <- result.try(
    envoy.get(\"LANGFUSE_SECRET_KEY\")
    |> result.replace_error(\"LANGFUSE_SECRET_KEY not set\"),
  )
  let base_url =
    envoy.get(\"LANGFUSE_BASE_URL\")
    |> result.unwrap(\"https://cloud.langfuse.com\")
  Ok(LangfuseCredentials(
    public_key: public_key,
    secret_key: secret_key,
    base_url: base_url,
  ))
}

fn fetch_langfuse_scores(
  creds: LangfuseCredentials,
  since: Option(String),
) -> Result(List(LangfuseScore), String) {
  let path = \"/api/public/scores\"
  let query = case since {
    None -> \"?limit=50\"
    Some(ts) -> \"?limit=50&fromTimestamp=\" <> ts
  }
  let auth_token = basic_auth(creds.public_key, creds.secret_key)

  use req <- result.try(
    request.to(creds.base_url <> path <> query)
    |> result.replace_error(\"failed to construct langfuse request\"),
  )
  let req =
    req
    |> request.set_header(\"authorization\", \"Basic \" <> auth_token)
    |> request.set_header(\"accept\", \"application/json\")

  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(e) { \"langfuse http error: \" <> string.inspect(e) }),
  )

  case resp.status {
    200 ->
      json.parse(resp.body, scores_response_decoder())
      |> result.map_error(fn(err) {
        \"failed to decode langfuse scores: \" <> string.inspect(err)
      })
    code ->
      Error(
        \"langfuse returned HTTP \"
        <> int.to_string(code)
        <> \": \"
        <> string.slice(resp.body, 0, 200),
      )
  }
}

fn scores_response_decoder() -> decode.Decoder(List(LangfuseScore)) {
  use scores <- decode.field(\"data\", decode.list(score_decoder()))
  decode.success(scores)
}

fn score_decoder() -> decode.Decoder(LangfuseScore) {
  use name <- decode.field(\"name\", decode.string)
  use string_value <- decode.field(
    \"stringValue\",
    decode.optional(decode.string),
  )
  use timestamp <- decode.field(\"timestamp\", decode.string)
  decode.success(LangfuseScore(
    name: name,
    string_value: string_value,
    timestamp: timestamp,
  ))
}

fn basic_auth(user: String, pass: String) -> String {
  bit_array.from_string(user <> \":\" <> pass)
  |> bit_array.base64_encode(False)
}

// ===========================================================================
// Dispatch (score → metric point)
// ===========================================================================

fn dispatch_scores(
  scores: List(LangfuseScore),
  signals: List(SignalEntry),
) -> List(DatadogPoint) {
  scores
  |> list.flat_map(fn(score) {
    signals
    |> list.filter(fn(s) { score_matches(score, s) })
    |> list.map(fn(s) {
      DatadogPoint(
        metric: s.metric,
        value: 1.0,
        timestamp: now_unix(),
        tags: s.tags,
      )
    })
  })
}

fn score_matches(score: LangfuseScore, signal: SignalEntry) -> Bool {
  signal.match
  |> dict.to_list
  |> list.all(fn(pair) {
    let #(field, expected) = pair
    case field {
      \"name\" -> score.name == expected
      \"value\" ->
        case score.string_value {
          Some(v) -> v == expected
          None -> False
        }
      _ -> False
    }
  })
}

// ===========================================================================
// Datadog client
// ===========================================================================

@external(erlang, \"erlang\", \"system_time\")
fn erlang_system_time_seconds(unit: SecondAtom) -> Int

type SecondAtom {
  Second
}

fn now_unix() -> Int {
  erlang_system_time_seconds(Second)
}

fn load_dd_api_key() -> Result(String, String) {
  envoy.get(\"DD_API_KEY\")
  |> result.replace_error(\"DD_API_KEY not set\")
}

fn submit_to_datadog(
  api_key: String,
  points: List(DatadogPoint),
) -> Result(Nil, String) {
  send_dd_series(api_key, score_points_series(points))
}

/// Emit relay self-observability metrics. Always called from `main` after
/// `run_with_stats` returns, regardless of success or failure, so a failed
/// run still increments the relevant error counter. Tagged uniformly with
/// `phase` on the error metric so operators can localize blame.
///
/// Lag is stubbed at 0 in v0 (the relay currently uses `now()` as the
/// score timestamp). A real `now - latest_score_timestamp` lands when the
/// ISO 8601 parser does.
fn emit_self_metrics(
  api_key: String,
  stats: RunStats,
  start: Int,
) -> Result(Nil, String) {
  let duration = now_unix() - start
  let series = self_metrics_series(stats, duration)
  send_dd_series(api_key, series)
}

fn self_metrics_series(stats: RunStats, duration: Int) -> List(json.Json) {
  let ts = now_unix()
  let heartbeat =
    series_entry(\"caffeine.relay.heartbeat\", 1, 1.0, ts, [])
  let scores =
    series_entry(
      \"caffeine.relay.scores_processed\",
      1,
      int.to_float(stats.scores_processed),
      ts,
      [],
    )
  let points =
    series_entry(
      \"caffeine.relay.metric_points_emitted\",
      1,
      int.to_float(stats.metric_points_emitted),
      ts,
      [],
    )
  let dur =
    // type=3 → gauge in the Datadog series API
    series_entry(
      \"caffeine.relay.run_duration_seconds\",
      3,
      int.to_float(duration),
      ts,
      [],
    )
  let lag = series_entry(\"caffeine.relay.lag_seconds\", 3, 0.0, ts, [])
  let outcome = case stats.failure_phase {
    None -> series_entry(\"caffeine.relay.runs_succeeded\", 1, 1.0, ts, [])
    Some(phase) ->
      series_entry(\"caffeine.relay.errors\", 1, 1.0, ts, [
        #(\"phase\", phase),
      ])
  }
  [heartbeat, scores, points, dur, lag, outcome]
}

fn series_entry(
  metric: String,
  type_: Int,
  value: Float,
  timestamp: Int,
  tags: List(#(String, String)),
) -> json.Json {
  let tag_strings =
    list.map(tags, fn(pair) { pair.0 <> \":\" <> pair.1 })
  json.object([
    #(\"metric\", json.string(metric)),
    #(\"type\", json.int(type_)),
    #(\"tags\", json.array(tag_strings, json.string)),
    #(
      \"points\",
      json.array(
        [#(timestamp, value)],
        fn(point) {
          let #(t, v) = point
          json.object([
            #(\"timestamp\", json.int(t)),
            #(\"value\", json.float(v)),
          ])
        },
      ),
    ),
  ])
}

/// Shared HTTP submitter so `submit_to_datadog` and `emit_self_metrics`
/// agree on auth + endpoint. Takes a pre-built series array.
fn send_dd_series(
  api_key: String,
  series: List(json.Json),
) -> Result(Nil, String) {
  case series {
    [] -> Ok(Nil)
    _ -> {
      let body =
        json.to_string(
          json.object([#(\"series\", json.preprocessed_array(series))]),
        )
      use req <- result.try(
        request.to(\"https://api.datadoghq.com/api/v2/series\")
        |> result.replace_error(\"failed to construct datadog request\"),
      )
      let req =
        req
        |> request.set_method(Post)
        |> request.set_header(\"dd-api-key\", api_key)
        |> request.set_header(\"content-type\", \"application/json\")
        |> request.set_body(body)
      use resp <- result.try(
        httpc.send(req)
        |> result.map_error(fn(e) {
          \"datadog http error: \" <> string.inspect(e)
        }),
      )
      case resp.status {
        202 -> Ok(Nil)
        code ->
          Error(
            \"datadog returned HTTP \"
            <> int.to_string(code)
            <> \": \"
            <> string.slice(resp.body, 0, 200),
          )
      }
    }
  }
}

/// Build the Datadog series JSON array from score-derived metric points.
/// Groups by (metric, tags) so each series-shape gets its own entry —
/// matters because multiple indicators (good / total) share a metric and
/// disambiguate by tag, so naive metric-only grouping would collapse them.
/// Maps to the Datadog `/api/v2/series` shape: `{metric, type, tags, points}`.
fn score_points_series(points: List(DatadogPoint)) -> List(json.Json) {
  points
  |> list.group(fn(p) { #(p.metric, tags_signature(p.tags)) })
  |> dict.to_list
  |> list.map(fn(pair) {
    let #(_key, ps) = pair
    let assert [first, ..] = ps
    json.object([
      #(\"metric\", json.string(first.metric)),
      // type=1 → count in the Datadog series API
      #(\"type\", json.int(1)),
      #(\"tags\", tags_for_series(first.tags)),
      #(
        \"points\",
        json.array(ps, fn(p) {
          json.object([
            #(\"timestamp\", json.int(p.timestamp)),
            #(\"value\", json.float(p.value)),
          ])
        }),
      ),
    ])
  })
}

/// Stable signature for a tags dict — used as a grouping key. Sorting by
/// key ensures two dicts with the same content but different insertion
/// order group together.
fn tags_signature(tags: dict.Dict(String, String)) -> String {
  tags
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { pair.0 <> \":\" <> pair.1 })
  |> string.join(\",\")
}

/// Datadog `/api/v2/series` expects tags as an array of `\"key:value\"` strings.
fn tags_for_series(tags: dict.Dict(String, String)) -> json.Json {
  tags
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { json.string(pair.0 <> \":\" <> pair.1) })
  |> json.preprocessed_array
}
"

const relay_gitignore = "build/
"
