import caffeine_lang/types/ast/basic_type

/// A SpecificationOfMetrics is a list of expected metric filters by name and type.
pub type SpecificationOfMetrics =
  List(basic_type.BasicType)
