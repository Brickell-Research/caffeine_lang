/// A source file with its path and content.
/// The path is retained for error messages and metadata extraction
/// (org/team/service from directory structure).
pub type SourceFile {
  SourceFile(path: String, content: String)
}
