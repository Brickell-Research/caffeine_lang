import caffeine_lang_v2/generator/common.{type GeneratorError}
import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/middle_end.{type IntermediateRepresentation}
import gleam/list
import gleam/option.{None}
import gleam/string
import terra_madre/render
import terra_madre/terraform.{type Resource}

/// Supported vendors for code generation
pub type Vendor {
  Datadog
}

/// Parse a vendor string into a Vendor type
pub fn parse_vendor(vendor_string: String) -> Result(Vendor, GeneratorError) {
  case string.lowercase(vendor_string) {
    "datadog" -> Ok(Datadog)
    _ -> Error(common.InvalidArtifact("Unknown vendor: " <> vendor_string))
  }
}

/// Generate terraform HCL from a list of IntermediateRepresentations
pub fn generate(
  irs: List(IntermediateRepresentation),
) -> Result(String, GeneratorError) {
  use resources <- result_try(generate_resources(irs))

  let config =
    terraform.Config(
      terraform: None,
      providers: [],
      variables: [],
      locals: [],
      data_sources: [],
      resources: resources,
      modules: [],
      outputs: [],
    )

  Ok(render.render_config(config))
}

/// Generate terraform resources from a list of IntermediateRepresentations
pub fn generate_resources(
  irs: List(IntermediateRepresentation),
) -> Result(List(Resource), GeneratorError) {
  // Group by artifact_ref and generate accordingly
  irs
  |> list.try_map(generate_resource)
}

/// Generate a single terraform resource from an IntermediateRepresentation
fn generate_resource(
  ir: IntermediateRepresentation,
) -> Result(Resource, GeneratorError) {
  case ir.artifact_ref {
    "SLO" -> generate_slo_resource(ir)
    other -> Error(common.InvalidArtifact(other))
  }
}

/// Generate an SLO resource, routing to the appropriate vendor
fn generate_slo_resource(
  ir: IntermediateRepresentation,
) -> Result(Resource, GeneratorError) {
  // Get vendor from IR values
  use vendor_string <- result_try(common.get_string_value(ir, "vendor"))
  use vendor <- result_try(parse_vendor(vendor_string))

  case vendor {
    Datadog -> datadog.generate_slo(ir)
  }
}

// Helper to work around Gleam's use syntax with Result
fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(err) -> Error(err)
  }
}
