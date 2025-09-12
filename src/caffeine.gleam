import caffeine/hello

// Main entry point for the Gleam application
pub fn main() {
  // When gleam_stdlib is available, uncomment this:
  // hello.greet("friend")
  // |> io.println

  // For now, we'll just call our functions to verify they work
  let _greeting1 = hello.greet("Gleam")
  let _greeting2 = hello.hello_world()

  // Return unit type
  Nil
}
