import caffeine/phase_4/terraform/datadog
import gleam/list
import gleam/string

pub type SupportedProvider {
  Datadog
}

pub fn build_provider(providers: List(SupportedProvider)) -> String {
  providers
  |> list.unique()
  |> list.map(do_build_provider)
  |> string.join("\n")
}

fn do_build_provider(provider: SupportedProvider) -> String {
  case provider {
    Datadog -> datadog.provider()
  }
}

pub fn build_backend() -> String {
  "terraform {
  backend \"local\" {
    path = \"terraform.tfstate\"
  }
}"
}

pub fn build_variables(providers: List(SupportedProvider)) -> String {
  providers
  |> list.unique()
  |> list.map(do_build_variables)
  |> string.join("\n")
}

fn do_build_variables(provider: SupportedProvider) -> String {
  case provider {
    Datadog -> datadog.variables()
  }
}

// pub fn build_slo_definitions() -> String {
//   todo
// }

// pub fn build_slo_dashboards() -> String {
//   todo
// }

// pub fn build_main() -> String {
//   let _backend = build_backend()
//   let _slo_definitions = build_slo_definitions()
//   let _slo_dashboards = build_slo_dashboards()
//   todo
// }

pub fn generate() -> String {
  // -- variables.tf --
  build_variables([Datadog])

  // -- providers.tf --
  build_provider([Datadog])
  // -- main.tf --
  // build_main()
}
