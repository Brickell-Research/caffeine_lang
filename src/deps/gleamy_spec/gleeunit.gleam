////
//// Gleamy Spec Gleeunit Module
////
//// This module re-exports gleeunit/should functionality while providing
//// a foundation for future BDD-style assertions and matchers.
////

import gleeunit
import gleeunit/should

// Re-export all gleeunit/should functionality
pub const be_error = should.be_error

pub const be_false = should.be_false

pub const be_ok = should.be_ok

pub const be_true = should.be_true

pub const equal = should.equal

pub const fail = should.fail

pub const not_equal = should.not_equal

pub const main = gleeunit.main
