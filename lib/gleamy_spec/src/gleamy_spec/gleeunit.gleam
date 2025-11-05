////
//// Gleamy Spec Gleeunit Module
////
//// This module re-exports gleeunit/should functionality while providing
//// a foundation for future BDD-style assertions and matchers.
////

import gleeunit/should as gleeunit

// Re-export all gleeunit/should functionality
pub const be_error = gleeunit.be_error

pub const be_false = gleeunit.be_false

pub const be_ok = gleeunit.be_ok

pub const be_true = gleeunit.be_true

pub const equal = gleeunit.equal

pub const fail = gleeunit.fail

pub const not_equal = gleeunit.not_equal
