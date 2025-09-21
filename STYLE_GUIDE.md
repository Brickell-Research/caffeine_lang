# Style Guide

* Directory Organized by Compiler Phase
  * Exceptions:
    * `common_types`
    * `cql` (caffeine query language)
* No unqualified imports
* types exist in a module named after the type within module name that makes sense according to their phase
* errors exist in a module named after the error which makes the full qualified import easier to consume
