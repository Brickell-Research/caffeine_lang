/// Shared keyword descriptions used by hover and completion.
pub type KeywordMeta {
  KeywordMeta(name: String, description: String)
}

/// All language keyword metadata.
pub fn all_keywords() -> List(KeywordMeta) {
  [
    KeywordMeta(
      name: "Measurements",
      description: "Declares a block of measurement definitions for one or more artifacts.",
    ),
    KeywordMeta(
      name: "Expectations",
      description: "Declares a block of expectation definitions for a measurement.",
    ),
    KeywordMeta(
      name: "measured",
      description: "Used with 'by' to specify which measurement an expectations block targets.",
    ),
    KeywordMeta(
      name: "by",
      description: "Used with 'measured' to specify which measurement an expectations block targets.",
    ),
    KeywordMeta(
      name: "extends",
      description: "Inherits fields from one or more extendable blocks.",
    ),
    KeywordMeta(
      name: "Requires",
      description: "Defines the typed parameters a measurement requires as input.",
    ),
    KeywordMeta(
      name: "Provides",
      description: "Defines the values a measurement or expectation provides as output.",
    ),
    KeywordMeta(
      name: "Type",
      description: "Declares a type alias, a named reusable refined type.",
    ),
  ]
}
