// ==== Artifacts ====
// ## SLO Specific - Queries (handled by CQL, outside of these checks) ##
// * ❌ too few params compared to value
// * ❌ too many params compared to value
// * ❌ different params compared to value
// ## SLO Specific - Sanity (technically input from lower configs) ##
// * ❌ threshold within a reasonable range
// * ❌ threshold correct type
// * ❌ window_in_days within a reasonable range/set
// * ❌ window_in_days correct type
// * ❌ window_in_days defaults as expected
// ## Cross-Field Validation ##
// * ❌ base_params and params have no key collisions (same param name in both)

// ==== Blueprints ====
// ## Reference Validation ##
// * ❌ artifact referenced by blueprint exists (success case)
// * ❌ artifact referenced by blueprint does not exist (error case)
// ## Inputs vs Artifact Params ##
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Template Validation ##
// * ❌ template variable references non-existent blueprint param (${undefined_var})
// * ❌ invalid template syntax (malformed ${...})
// * ❌ blueprint params key collision/shadowing with artifact's base_params

// ==== Expectations ====
// ## Reference Validation ##
// * ❌ blueprint referenced by expectation exists (success case)
// * ❌ blueprint referenced by expectation does not exist (error case)
// ## Inputs vs Blueprint Params ##
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Additional Input Validation ##
// * ❌ inputs for non-existent blueprint params (extra/unknown inputs)
// * ❌ type coercion validation (e.g., "abc" when Integer expected)

// ==== Cross-Cutting / Chain Validation ====
// * ❌ full valid chain: Artifact → Blueprint → Expectation (success case)
// * ❌ base_params types propagate correctly through blueprint to expectation
// * ❌ expectation input coercible to artifact base_params type
// * ❌ expectation names unique across all expectation files (linker handles per-file)
// * ❌ blueprint names unique across all blueprint files (parser handles per-file)

// ==== Type-Specific Validation ====
// * ❌ expected Boolean, got other scalar
// * ❌ expected Integer, got Float
// * ❌ expected String, got numeric
// * ❌ expected NonEmptyList(T), got scalar
// * ❌ empty list for NonEmptyList(T)
// * ❌ expected Optional(T), got wrong inner type
// * ❌ expected Dict(String, T), got scalar

// ==== Default/Optional Handling ====
// * ❌ optional param omitted → uses default
// * ❌ optional param provided → overrides default
// * ❌ default via -> operator parsed and applied
