import caffeine_lang/phase_2/ast/types as ast_types
import gleam/io
import simplifile

pub fn generate(
  _organization: ast_types.Organization,
  output_directory: String,
) -> Result(Nil, simplifile.FileError) {
  io.println("Writing to file " <> output_directory <> "/generated.txt")
  let _ = simplifile.delete(output_directory <> "/generated.txt")
  let _ = simplifile.create_file(output_directory <> "/generated.txt")
  let _ =
    simplifile.append(
      output_directory <> "/generated.txt",
      "Hello world - generated successfully after finishing semantic analysis!",
    )
  Ok(Nil)
}
