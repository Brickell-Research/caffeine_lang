//// Static manifest of metrics this relay emits. Generated from the relay
//// declaration — do not edit by hand. The runner imports this to get its
//// scorer allowlist; downstream language tooling will import it to
//// type-check measurement references.

import gleam/option.{type Option}

pub type ScorerInfo {
  ScorerInfo(
    name: String,
    data_type: String,
    count_metric: String,
    value_metric: Option(String),
  )
}

pub const metric_prefix: String = "{{METRIC_PREFIX}}"

pub const relay_name: String = "{{RELAY_NAME}}"

pub fn scorers() -> List(ScorerInfo) {
  [
{{SCORER_ENTRIES}}  ]
}
