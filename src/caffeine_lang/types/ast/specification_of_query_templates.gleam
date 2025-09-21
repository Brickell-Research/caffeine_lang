import caffeine_lang/types/ast/basic_type

/// A SpecificationOfQueryTemplates is a list of expected basic types by name and type.
pub type SpecificationOfQueryTemplates =
  List(basic_type.BasicType)
