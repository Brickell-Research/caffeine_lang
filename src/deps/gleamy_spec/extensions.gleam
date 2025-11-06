////
//// Gleamy Spec Extensions Module
////
//// This module implements BDD-style describe and it blocks as inspired by RSpec.
////

pub fn describe(_name: String, body: fn() -> void) -> void {
  body()
}

pub fn it(_name: String, body: fn() -> void) -> void {
  body()
}
