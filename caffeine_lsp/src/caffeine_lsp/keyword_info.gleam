/// Shared keyword descriptions used by hover and completion.
pub type KeywordMeta {
  KeywordMeta(name: String, description: String)
}

/// All language keyword metadata.
pub fn all_keywords() -> List(KeywordMeta) {
  [
    KeywordMeta(
      name: "Blueprints",
      description: "Declares a block of blueprint definitions for one or more artifacts.",
    ),
    KeywordMeta(
      name: "Expectations",
      description: "Declares a block of expectation definitions for a blueprint.",
    ),
    KeywordMeta(
      name: "for",
      description: "Specifies which artifacts a blueprint block targets.",
    ),
    KeywordMeta(
      name: "extends",
      description: "Inherits fields from one or more extendable blocks.",
    ),
    KeywordMeta(
      name: "Requires",
      description: "Defines the typed parameters a blueprint requires as input.",
    ),
    KeywordMeta(
      name: "Provides",
      description: "Defines the values a blueprint or expectation provides as output.",
    ),
    KeywordMeta(
      name: "Type",
      description: "Declares a type alias, a named reusable refined type.",
    ),
  ]
}
