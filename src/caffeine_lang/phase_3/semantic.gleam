import caffeine_lang/errors/semantic as semantic_errors
import caffeine_lang/types/ast/organization

pub fn perform_semantic_analysis(
  _organization: organization.Organization,
) -> Result(Bool, semantic_errors.SemanticAnalysisError) {
  Ok(True)
}
