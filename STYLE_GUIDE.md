# Style Guide

* Directory Organized by Compiler Phase
  * Exceptions:
    * `common_types`
    * `cql` (caffeine query language)
* No unqualified imports
* Types are organized by feature/domain, not by technical category
  * Types are defined in the module where they're primarily used
  * Types live alongside functions that operate on them
  * Use submodules to organize complex domains, but they should also contain related functions
  * Avoid separating all types into a single "types" directory
  * Common types that are truly ubiquitous across phases may live in a common module
* Errors exist in a module named after the error which makes the full qualified import easier to consume
