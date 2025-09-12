// Simple hello module without external dependencies

/// Greets a person with a friendly message
pub fn greet(name: String) -> String {
  // String concatenation using <> operator is built-in
  "Hello, " <> name <> "!"
}

/// Returns a generic greeting
pub fn hello_world() -> String {
  "Hello, World!"
}
