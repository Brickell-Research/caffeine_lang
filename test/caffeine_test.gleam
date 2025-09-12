// Simple test without external dependencies
import caffeine/hello

import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn greet_test() {
  assert hello.greet("Alice") == "Hello, Alice!"
}
