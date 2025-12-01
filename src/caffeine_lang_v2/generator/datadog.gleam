import gleam/option
import terra_madre/hcl
import terra_madre/terraform

pub fn build_provider() -> terraform.Provider {
  terraform.simple_provider("datadog", [
    #("api_key", hcl.ref("var.datadog_api_key")),
    #("app_key", hcl.ref("var.datadog_app_key")),
  ])
}

pub fn build_provider_requirement() -> terraform.ProviderRequirement {
  terraform.ProviderRequirement(source: "DataDog/datadog", version: option.None)
}
