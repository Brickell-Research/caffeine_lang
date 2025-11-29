import caffeine_lang_v2/common/ast.{type AST}

pub fn perform(abs_syn_tree: AST) -> Result(Bool, String) {
  case abs_syn_tree {
    ast.AST([], _, _) -> Error("Expected at least one artifact.")
    ast.AST(_, [], _) -> Error("Expected at least one blueprint.")
    ast.AST(_, _, []) -> Error("Expected at least one expectation.")
    _ -> Ok(True)
  }
}
