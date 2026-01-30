import gleam/json
import gleam/list

// LSP CompletionItemKind constants
const kind_keyword = 14

const kind_class = 7

/// Returns a list of completion item JSON objects.
/// Phase 1: static list of all keywords and type names.
pub fn get_completions() -> List(json.Json) {
  list.flatten([keyword_items(), type_items()])
}

fn keyword_items() -> List(json.Json) {
  [
    completion_item("Blueprints", kind_keyword, "Declare a blueprints block"),
    completion_item("Expectations", kind_keyword, "Declare an expectations block"),
    completion_item("for", kind_keyword, "Specify target artifacts"),
    completion_item("extends", kind_keyword, "Inherit from extendable blocks"),
    completion_item("Requires", kind_keyword, "Define required typed parameters"),
    completion_item("Provides", kind_keyword, "Define provided values"),
    completion_item("Type", kind_keyword, "Declare a type alias"),
  ]
}

fn type_items() -> List(json.Json) {
  [
    completion_item("String", kind_class, "Any text between double quotes"),
    completion_item("Integer", kind_class, "Whole numbers"),
    completion_item("Float", kind_class, "Decimal numbers"),
    completion_item("Boolean", kind_class, "True or false"),
    completion_item("URL", kind_class, "A valid URL (http:// or https://)"),
    completion_item("List", kind_class, "An ordered sequence: List(T)"),
    completion_item("Dict", kind_class, "A key-value map: Dict(K, V)"),
    completion_item("Optional", kind_class, "Value may be unspecified: Optional(T)"),
    completion_item("Defaulted", kind_class, "Value with default: Defaulted(T, default)"),
  ]
}

fn completion_item(
  label: String,
  kind: Int,
  detail: String,
) -> json.Json {
  json.object([
    #("label", json.string(label)),
    #("kind", json.int(kind)),
    #("detail", json.string(detail)),
  ])
}
