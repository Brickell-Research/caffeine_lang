/// Codegen for the relay routing table (`signals.json`).
///
/// Walks resolved IRs and emits one routing entry per external-signal
/// indicator. The relay binary consumes this file at runtime to decide
/// which incoming source events (e.g. Langfuse scores) map to which
/// Datadog metrics, and what tags to attach.
///
/// Metric naming convention: `caffeine.<unique_identifier>` — ONE metric
/// per expectation. The per-indicator routing entries all share that
/// metric name and disambiguate by writing an `indicator:<name>` tag on
/// every emitted data point. This matches the synthesis function in
/// `codegen/datadog.gleam` (`sum:caffeine.<unique>{indicator:<name>}`)
/// and the idiomatic Datadog metric-SLO shape.
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, type Resolved, ExternalSignal,
}
import caffeine_lang/value
import gleam/dict
import gleam/json
import gleam/list
import gleam/option
import gleam/string

/// Routing entry for one external-signal indicator. The fields mirror what
/// the relay binary needs at runtime: which source kind to pull from, which
/// events to match, what metric to emit, what tags to attach, and how to
/// extract a numeric value (if any).
pub type SignalEntry {
  SignalEntry(
    metric: String,
    kind: SignalKind,
    source: String,
    match: dict.Dict(String, value.Value),
    tags: dict.Dict(String, String),
    value_path: option.Option(String),
  )
}

/// `Count` increments the metric by 1 per matching event. `Distribution`
/// extracts a numeric value at `value_path` per matching event. The
/// distinction maps directly to Datadog metric submission shape.
pub type SignalKind {
  Count
  Distribution
}

/// Generate the `signals.json` content for a list of resolved IRs. Returns
/// `None` when no IR uses external-signal indicators — the file isn't worth
/// emitting if the relay has nothing to route.
@internal
pub fn generate(
  irs: List(IntermediateRepresentation(Resolved)),
) -> option.Option(String) {
  let entries = list.flat_map(irs, ir_to_signal_entries)
  case entries {
    [] -> option.None
    _ -> option.Some(json.to_string(signals_json(entries)))
  }
}

/// Build the list of signal entries from a single resolved IR by walking
/// `slo.indicators` for `ExternalSignal` variants. Literal-query indicators
/// are skipped — they don't need relay routing. Entries are sorted by
/// indicator name for deterministic output across compile targets.
fn ir_to_signal_entries(
  ir: IntermediateRepresentation(Resolved),
) -> List(SignalEntry) {
  ir.slo.indicators
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.filter_map(fn(pair) {
    let #(name, src) = pair
    case src {
      ExternalSignal(source, match, value_extraction) ->
        Ok(SignalEntry(
          // One metric per measurement; per-indicator routing entries
          // disambiguate by writing an `indicator:<name>` tag.
          metric: "caffeine." <> ir.unique_identifier,
          kind: case value_extraction {
            option.None -> Count
            option.Some(_) -> Distribution
          },
          source: source,
          match: match,
          tags: dict.from_list([#("indicator", name)]),
          value_path: option.map(value_extraction, fn(ve) { ve.path }),
        ))
      _ -> Error(Nil)
    }
  })
}

/// Wrap a list of entries in the top-level `signals.json` object: a version
/// tag plus the routing array. Schema version 2 adds the per-entry `tags`
/// field; relay builds before 2026-05-23 read v1 and don't know about tags.
fn signals_json(entries: List(SignalEntry)) -> json.Json {
  json.object([
    #("version", json.int(2)),
    #("signals", json.array(entries, signal_entry_json)),
  ])
}

fn signal_entry_json(entry: SignalEntry) -> json.Json {
  json.object([
    #("metric", json.string(entry.metric)),
    #("kind", json.string(signal_kind_to_string(entry.kind))),
    #("source", json.string(entry.source)),
    #("match", match_dict_json(entry.match)),
    #("tags", tags_dict_json(entry.tags)),
    #("value_path", case entry.value_path {
      option.None -> json.null()
      option.Some(p) -> json.string(p)
    }),
  ])
}

/// Serialize the `tags` dict — already `Dict(String, String)` because every
/// codegen-emitted tag is a string. Sorted by key for deterministic output.
fn tags_dict_json(tags: dict.Dict(String, String)) -> json.Json {
  tags
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
  |> json.object
}

fn signal_kind_to_string(kind: SignalKind) -> String {
  case kind {
    Count -> "count"
    Distribution -> "distribution"
  }
}

/// Serialize a `match` dict. Match values are runtime-untyped at the relay,
/// so we emit each as its nearest JSON shape. Strings stay strings; numeric
/// and boolean values keep their JSON-native form. Other shapes fall back
/// to `null` (shouldn't appear post-validate). Entries are sorted by key for
/// deterministic output across compile targets — `dict.to_list` doesn't
/// guarantee insertion order on JavaScript.
fn match_dict_json(match: dict.Dict(String, value.Value)) -> json.Json {
  match
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { #(pair.0, match_value_json(pair.1)) })
  |> json.object
}

fn match_value_json(v: value.Value) -> json.Json {
  case v {
    value.StringValue(s) -> json.string(s)
    value.IntValue(i) -> json.int(i)
    value.FloatValue(f) -> json.float(f)
    value.BoolValue(b) -> json.bool(b)
    _ -> json.null()
  }
}
