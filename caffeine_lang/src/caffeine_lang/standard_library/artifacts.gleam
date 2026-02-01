/// The standard library artifacts embedded at compile time.
/// This ensures the binary is self-contained and doesn't need external files.
///
/// At some point it's a bit silly to make this a json string to just parse it, however
/// when we decide to expand this or enable external artifacts, we'll want to keep the
/// artifacts json parser in the compilation pipeline.
///
/// Notes:
///   * window_in_days is defaulted to 30 days
pub const standard_library = "
{
  \"artifacts\": [
    {
      \"type_\": \"SLO\",
      \"description\": \"A Service Level Objective that monitors a metric query against a threshold over a rolling window.\",
      \"params\": {
        \"threshold\": { \"type_\": \"Float { x | x in ( 0.0..100.0 ) }\", \"description\": \"Target percentage (e.g., 99.9)\" },
        \"window_in_days\": { \"type_\": \"Defaulted(Integer, 30)\", \"description\": \"Rolling window for measurement\" },
        \"indicators\": { \"type_\": \"Dict(String, String)\", \"description\": \"Named SLI measurement expressions\" },
        \"evaluation\": { \"type_\": \"String\", \"description\": \"How to evaluate indicators as an SLI\" },
        \"vendor\": { \"type_\": \"String { x | x in { datadog, honeycomb } }\", \"description\": \"Observability platform\" },
        \"tags\": { \"type_\": \"Optional(Dict(String, String))\", \"description\": \"An optional set of tags to append to the SLO artifact\" },
        \"runbook\": { \"type_\": \"Optional(URL)\", \"description\": \"An optional runbook URL surfaced via the SLO description\" }
      }
    },
    {
      \"type_\": \"DependencyRelations\",
      \"description\": \"Declares soft and hard dependencies between services for dependency mapping.\",
      \"params\": {
        \"relations\": { \"type_\": \"Dict(String { x | x in { soft, hard } }, List(String))\", \"description\": \"Map of dependency type to list of service names\" }
      }
    }
  ]
}
"
