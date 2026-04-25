import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/dynatrace
import caffeine_lang/codegen/generator_utils
import caffeine_lang/codegen/honeycomb
import caffeine_lang/codegen/newrelic
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/linker/ir.{type IntermediateRepresentation, type Resolved}
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import terra_madre/hcl
import terra_madre/terraform

/// Declarative configuration for a vendor's Terraform output:
/// the provider block, required-providers metadata, input variables,
/// and the function that turns IRs into Terraform resources.
pub type Platform {
  Platform(
    vendor: vendor.Vendor,
    provider_name: String,
    provider_source: String,
    provider_version: String,
    provider_attributes: List(#(String, hcl.Expr)),
    variables: List(terraform.Variable),
    generate_resources: fn(List(IntermediateRepresentation(Resolved))) ->
      Result(#(List(terraform.Resource), List(String)), CompilationError),
  )
}

/// All supported platforms. Order is stable for deterministic output.
pub fn all() -> List(Platform) {
  [datadog_platform(), honeycomb_platform(), dynatrace_platform(), newrelic_platform()]
}

/// Look up the platform configuration for a given vendor.
/// Total: every Vendor variant has a corresponding Platform.
pub fn for_vendor(v: vendor.Vendor) -> Platform {
  let assert Ok(p) = list.find(all(), fn(p) { p.vendor == v })
  p
}

/// Derive the TerraformSettings block for a platform.
pub fn terraform_settings(p: Platform) -> terraform.TerraformSettings {
  terraform.TerraformSettings(
    required_version: option.None,
    required_providers: dict.from_list([
      #(
        p.provider_name,
        terraform.ProviderRequirement(
          p.provider_source,
          option.Some(p.provider_version),
        ),
      ),
    ]),
    backend: option.None,
    cloud: option.None,
  )
}

/// Derive the Provider block for a platform.
pub fn provider(p: Platform) -> terraform.Provider {
  terraform.Provider(
    name: p.provider_name,
    alias: option.None,
    attributes: dict.from_list(p.provider_attributes),
    blocks: [],
  )
}

/// Generate complete Terraform output (boilerplate + resources) for a platform.
/// Used in tests to produce full HCL for a single vendor in isolation.
pub fn generate_terraform(
  p: Platform,
  irs: List(IntermediateRepresentation(Resolved)),
) -> Result(#(String, List(String)), CompilationError) {
  use #(resources, warnings) <- result.try(p.generate_resources(irs))
  Ok(#(
    generator_utils.render_terraform_config(
      resources: resources,
      settings: terraform_settings(p),
      providers: [provider(p)],
      variables: p.variables,
    ),
    warnings,
  ))
}

// ==== Per-vendor platform definitions ====

fn datadog_platform() -> Platform {
  Platform(
    vendor: vendor.Datadog,
    provider_name: constants.provider_datadog,
    provider_source: "DataDog/datadog",
    provider_version: "~> 3.0",
    provider_attributes: [
      #("api_key", hcl.ref("var.datadog_api_key")),
      #("app_key", hcl.ref("var.datadog_app_key")),
    ],
    variables: [
      sensitive_string("datadog_api_key", "Datadog API key"),
      sensitive_string("datadog_app_key", "Datadog Application key"),
    ],
    generate_resources: datadog.generate_resources,
  )
}

fn honeycomb_platform() -> Platform {
  Platform(
    vendor: vendor.Honeycomb,
    provider_name: constants.provider_honeycombio,
    provider_source: "honeycombio/honeycombio",
    provider_version: "~> 0.31",
    provider_attributes: [#("api_key", hcl.ref("var.honeycomb_api_key"))],
    variables: [
      sensitive_string("honeycomb_api_key", "Honeycomb API key"),
      plain_string("honeycomb_dataset", "Honeycomb dataset slug"),
    ],
    generate_resources: honeycomb.generate_resources,
  )
}

fn dynatrace_platform() -> Platform {
  Platform(
    vendor: vendor.Dynatrace,
    provider_name: constants.provider_dynatrace,
    provider_source: "dynatrace-oss/dynatrace",
    provider_version: "~> 1.0",
    provider_attributes: [
      #("dt_env_url", hcl.ref("var.dynatrace_env_url")),
      #("dt_api_token", hcl.ref("var.dynatrace_api_token")),
    ],
    variables: [
      plain_string("dynatrace_env_url", "Dynatrace environment URL"),
      sensitive_string("dynatrace_api_token", "Dynatrace API token"),
    ],
    generate_resources: dynatrace.generate_resources,
  )
}

fn newrelic_platform() -> Platform {
  Platform(
    vendor: vendor.NewRelic,
    provider_name: constants.provider_newrelic,
    provider_source: "newrelic/newrelic",
    provider_version: "~> 3.0",
    provider_attributes: [
      #("account_id", hcl.ref("var.newrelic_account_id")),
      #("api_key", hcl.ref("var.newrelic_api_key")),
      #("region", hcl.ref("var.newrelic_region")),
    ],
    variables: [
      typed_var("newrelic_account_id", "number", "New Relic account ID", False),
      sensitive_string("newrelic_api_key", "New Relic API key"),
      terraform.Variable(
        name: "newrelic_region",
        type_constraint: option.Some(hcl.Identifier("string")),
        default: option.Some(hcl.StringLiteral("US")),
        description: option.Some("New Relic region"),
        sensitive: option.None,
        nullable: option.None,
        validation: [],
      ),
      plain_string("newrelic_entity_guid", "New Relic entity GUID"),
    ],
    generate_resources: newrelic.generate_resources,
  )
}

// ==== Variable constructors ====

fn typed_var(
  name: String,
  type_: String,
  description: String,
  sensitive: Bool,
) -> terraform.Variable {
  terraform.Variable(
    name: name,
    type_constraint: option.Some(hcl.Identifier(type_)),
    default: option.None,
    description: option.Some(description),
    sensitive: case sensitive {
      True -> option.Some(True)
      False -> option.None
    },
    nullable: option.None,
    validation: [],
  )
}

fn sensitive_string(name: String, description: String) -> terraform.Variable {
  typed_var(name, "string", description, True)
}

fn plain_string(name: String, description: String) -> terraform.Variable {
  typed_var(name, "string", description, False)
}
