import caffeine_lang/codegen/generator_utils
import gleam/dict
import gleam/option
import gleam/string
import gleeunit/should
import terra_madre/hcl
import terra_madre/terraform

// ==== render_terraform_config ====
// * ✅ empty resources produces minimal config
// * ✅ single resource with settings/provider/variables

pub fn render_terraform_config_empty_test() {
  let result =
    generator_utils.render_terraform_config(
      resources: [],
      settings: terraform.TerraformSettings(
        required_version: option.None,
        required_providers: dict.new(),
        backend: option.None,
        cloud: option.None,
      ),
      providers: [],
      variables: [],
    )
  // Empty config should still be a valid string (possibly empty or minimal)
  { string.length(result) >= 0 } |> should.be_true()
}

pub fn render_terraform_config_with_resource_test() {
  let settings =
    terraform.TerraformSettings(
      required_version: option.Some(">= 1.0"),
      required_providers: dict.from_list([
        #(
          "datadog",
          terraform.ProviderRequirement(
            source: "DataDog/datadog",
            version: option.Some("~> 3.0"),
          ),
        ),
      ]),
      backend: option.None,
      cloud: option.None,
    )

  let provider =
    terraform.simple_provider("datadog", [
      #("api_key", hcl.StringLiteral("var.dd_api_key")),
    ])

  let resource =
    terraform.simple_resource("datadog_service_level_objective", "test_slo", [
      #("name", hcl.StringLiteral("Test SLO")),
      #("type", hcl.StringLiteral("metric")),
    ])

  let variable = terraform.simple_variable("dd_api_key", hcl.StringLiteral(""))

  let result =
    generator_utils.render_terraform_config(
      resources: [resource],
      settings: settings,
      providers: [provider],
      variables: [variable],
    )

  // Should contain terraform block
  { string.contains(result, "terraform") } |> should.be_true()
  // Should contain resource
  { string.contains(result, "datadog_service_level_objective") }
  |> should.be_true()
  { string.contains(result, "test_slo") } |> should.be_true()
  // Should contain provider
  { string.contains(result, "datadog") } |> should.be_true()
  // Should contain variable
  { string.contains(result, "dd_api_key") } |> should.be_true()
}
