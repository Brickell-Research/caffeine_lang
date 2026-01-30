import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/common/type_info.{type TypeMeta}
import caffeine_lsp/keyword_info
import gleam/json
import gleam/list

// LSP CompletionItemKind constants
const kind_keyword = 14

const kind_class = 7

/// Returns a list of completion item JSON objects.
pub fn get_completions() -> List(json.Json) {
  list.flatten([keyword_items(), type_items()])
}

fn keyword_items() -> List(json.Json) {
  keyword_info.all_keywords()
  |> list.map(fn(kw) {
    completion_item(kw.name, kind_keyword, kw.description)
  })
}

fn type_items() -> List(json.Json) {
  all_type_metas()
  |> list.map(fn(m: TypeMeta) {
    completion_item(m.name, kind_class, m.description)
  })
}

fn all_type_metas() -> List(TypeMeta) {
  list.flatten([
    primitive_types.all_type_metas(),
    collection_types.all_type_metas(),
    modifier_types.all_type_metas(),
    refinement_types.all_type_metas(),
  ])
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
