import caffeine_lang/errors/semantic as semantic_errors
import caffeine_lang/phase_2/linker/organization

pub fn perform_semantic_analysis(
  _organization: organization.Organization,
) -> Result(Bool, semantic_errors.SemanticAnalysisError) {
  Ok(True)
}
