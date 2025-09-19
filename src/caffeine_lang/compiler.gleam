import caffeine_lang/phase_2/linker/organization/linker
import caffeine_lang/phase_3/semantic
import caffeine_lang/phase_4/slo_resolver
import caffeine_lang/phase_5/terraform/generator
import gleam/io

pub fn compile(
  specification_directory: String,
  instantiation_directory: String,
  output_directory: String,
) -> Nil {
  io.println("1️⃣ Compiling...")
  io.println("\tSpecification directory: " <> specification_directory)
  io.println("\tInstantiation directory: " <> instantiation_directory)
  io.println("\tOutput directory: " <> output_directory)
  let organization_result =
    linker.link_specification_and_instantiation(
      specification_directory,
      instantiation_directory,
    )

  case organization_result {
    Ok(organization) -> {
      io.println("2️⃣ Parsed and linked successfully!")
      let result = semantic.perform_semantic_analysis(organization)
      case result {
        Ok(_) -> {
          io.println("3️⃣ Semantic analysis successful!")
          io.println("4️⃣ Resolving SLOs...")
          let resolved_slos = slo_resolver.resolve_slos(organization)
          io.println("Resolved SLOs successfully!")
          case resolved_slos {
            Ok(resolved_slos) -> {
              io.println("5️⃣ Generating...")
              let _generated =
                generator.generate(resolved_slos, output_directory)
              io.println("🎉Generated successfully!")
            }
            Error(e) -> {
              io.println_error(e)
            }
          }
        }
        Error(e) -> {
          case e {
            semantic.UndefinedServiceError(_service_names) ->
              io.println_error("Undefined service error.")
            semantic.UndefinedSliTypeError(_sli_type_names) ->
              io.println_error("Undefined sli type error.")
            semantic.InvalidSloThresholdError(_thresholds) ->
              io.println_error("Invalid sli threshold error.")
            semantic.DuplicateServiceError(_service_names) ->
              io.println_error("Duplicate service error.")
          }
        }
      }
    }
    Error(e) -> io.println_error(e)
  }
}
