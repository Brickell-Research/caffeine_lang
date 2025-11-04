////
//// Gleamy Spec - A behavior-driven development test framework for Gleam
//// 
//// This module provides a proxy interface to gleeunit while laying the groundwork
//// for future RSpec-like functionality including describe blocks, let bindings,
//// nested contexts, and other BDD features.
////
//// For now, this acts as a drop-in replacement for gleeunit.
////

import gleeunit

/// Run all tests in the current package.
/// This is a proxy to gleeunit.main() for compatibility.
pub fn main() {
  gleeunit.main()
}
