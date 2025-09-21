pub type SemanticAnalysisError {
  UndefinedServiceError(service_names: List(String))
  UndefinedSliTypeError(sli_type_names: List(String))
  InvalidSloThresholdError(thresholds: List(Float))
  DuplicateServiceError(service_names: List(String))
}
