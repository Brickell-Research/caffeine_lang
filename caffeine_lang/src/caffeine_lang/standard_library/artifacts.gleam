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
        \"window_in_days\": { \"type_\": \"Defaulted(Integer, 30) { x | x in { 7, 30, 90 } }\", \"description\": \"Rolling window for measurement\" },
        \"queries\": { \"type_\": \"Dict(String, String)\", \"description\": \"Named queries for the SLI calculation\" },
        \"value\": { \"type_\": \"String\", \"description\": \"CQL expression combining queries\" },
        \"vendor\": { \"type_\": \"String { x | x in { datadog } }\", \"description\": \"Observability platform\" }
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
