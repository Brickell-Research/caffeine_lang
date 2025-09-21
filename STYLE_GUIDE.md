# Style Guide

* Directory Organized by Compiler Phase
  * Exceptions:
    * `common_types`
    * `cql` (caffeine query language)
* Types exist in a `types` file
  * When imported, name qualified import, i.e. `import caffeine_lang/phase_1/unresolved/types as unresolved_types`
* Errors exist in an `errors` file
  * Module scheme should reflect the name of the error which makes the full qualified import easier to consume, i.e. `import caffeine_lang/phase_1/semantic/errors as semantic_errors`
* No unqualified imports
