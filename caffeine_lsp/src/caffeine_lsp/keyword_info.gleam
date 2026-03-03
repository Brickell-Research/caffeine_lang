/// Shared keyword descriptions used by hover and completion.
pub type KeywordMeta {
  KeywordMeta(name: String, description: String)
}

/// All language keyword metadata.
pub fn all_keywords() -> List(KeywordMeta) {
  [
    KeywordMeta(
      name: "Blueprints",
      description: "Declares a block of blueprint definitions.",
    ),
    KeywordMeta(
      name: "Expectations",
      description: "Declares a block of expectation definitions for a blueprint.",
    ),
    KeywordMeta(
      name: "extends",
      description: "Inherits fields from one or more extendable blocks.",
    ),
    KeywordMeta(
      name: "Requiring",
      description: "Defines the typed parameters a blueprint requires as input.",
    ),
    KeywordMeta(
      name: "Provides",
      description: "Defines the values an expectation provides as output.",
    ),
    KeywordMeta(
      name: "signals",
      description: "Defines the signal queries a blueprint provides for monitoring.",
    ),
    KeywordMeta(
      name: "success_rate",
      description: "Declares a success rate evaluation type (numerator/denominator ratio).",
    ),
    KeywordMeta(
      name: "time_slice",
      description: "Declares a time slice evaluation type (threshold-based query).",
    ),
    KeywordMeta(
      name: "Type",
      description: "Declares a type alias, a named reusable refined type.",
    ),
  ]
}
