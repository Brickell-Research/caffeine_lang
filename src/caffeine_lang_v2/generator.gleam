import caffeine_lang_v2/common/ast
import caffeine_lang_v2/parser/expectations
import gleam/io
import gleam/list

pub fn generate(abstract_syntax_tree: ast.AST) {
  io.println("Generate!")

  abstract_syntax_tree.expectations
  |> list.map(expectations.get_name)
  |> list.each(io.println)
}
