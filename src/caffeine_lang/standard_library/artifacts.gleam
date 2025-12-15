/// The standard library artifacts embedded at compile time.
/// This ensures the binary is self-contained and doesn't need external files.
/// 
/// At some point it's a bit silly to make this a json string to just parse it, however
/// when we decide to expand this or enable external artifacts, we'll want to keep the
/// artifacts json parser in the compilation pipeline.
pub const standard_library = "
{
  \"artifacts\": [
    {
      \"name\": \"SLO\",
      \"version\": \"0.0.1\",
      \"inherited_params\": { \"threshold\": \"Float\", \"window_in_days\": \"Integer\" },
      \"required_params\": { \"queries\": \"Dict(String, String)\", \"value\": \"String\", \"vendor\": \"String\"}
    }
  ]
}
"
