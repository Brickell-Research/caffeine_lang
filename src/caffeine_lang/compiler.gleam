import caffeine_lang/phase_2/linker/organization/linker
import caffeine_lang/phase_3/semantic
import caffeine_lang/phase_5/smoke_test
import gleam/io

pub fn compile(
  specification_directory: String,
  instantiation_directory: String,
) -> Nil {
  io.println("1️⃣ Compiling...")
  io.println("\tSpecification directory: " <> specification_directory)
  io.println("\tInstantiation directory: " <> instantiation_directory)
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
          io.println("4️⃣ Generating...")
          let _ =
            smoke_test.generate(
              organization,
              "test/artifacts/some_organization",
            )
          io.println("🎉Generated successfully!")
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
