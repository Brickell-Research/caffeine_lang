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
      \"name\": \"SLO\",
      \"params\": { \"threshold\": \"Float\", \"window_in_days\": \"Defaulted(Integer, 30) { x | x in { 7, 30, 90 } }\", \"queries\": \"Dict(String, String)\", \"value\": \"String\", \"vendor\": \"String { x | x in { datadog } }\"}
    }
  ]
}
"
