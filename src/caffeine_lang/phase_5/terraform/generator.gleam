import caffeine_lang/phase_5/terraform/datadog
import caffeine_lang/types/intermediate_representation.{type ResolvedSlo}
import gleam/io
import gleam/list
import gleam/string
import simplifile

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

pub fn build_slo_definitions(slos: List(ResolvedSlo)) -> String {
  slos
  |> list.map(datadog.full_resource_body)
  |> string.join("\n\n")
}

pub fn build_main(slos: List(ResolvedSlo)) -> String {
  let backend = build_backend()
  let slo_definitions = build_slo_definitions(slos)
  backend <> "\n\n" <> slo_definitions
}

pub fn generate(
  slos: List(ResolvedSlo),
  output_directory: String,
) -> Result(Nil, simplifile.FileError) {
  let content =
    build_variables([Datadog])
    <> "\n\n"
    <> build_provider([Datadog])
    <> "\n\n"
    <> build_main(slos)

  io.println("Writing to file " <> output_directory <> "/generated.txt")
  let _ = simplifile.delete(output_directory <> "/generated.txt")
  let _ = simplifile.create_file(output_directory <> "/generated.txt")
  let _ = simplifile.append(output_directory <> "/generated.txt", content)
  Ok(Nil)
}
