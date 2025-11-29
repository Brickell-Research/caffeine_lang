// ==== Artifacts - SLO Specific ====
// ## Queries - technically input from lower configs ##
// The following are handled by CQL, outside of these checks
// * ❌ too few params compared to value
// * ❌ too many params compared to value
// * ❌ different params compared to value
// ## Sanity - technically input from lower configs ##
// * ❌ threshold within a reasonable range
// * ❌ threshold correct type
// * ❌ window_in_days within a reasonable range/set
// * ❌ window_in_days correct type
// * ❌ window_in_days defaults as expected

// ==== Blueprints ====
// ## Input ##
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Sanity Checks ##
// * ❌ artifact referenced by blueprint exists

// ==== Expectations ====
// ## Input ##
// * ❌ wrong type in inputs
// * ❌ too few inputs
// * ❌ too many inputs
// * ❌ different input fields
// ## Sanity Checks ##
// * ❌ blueprint referenced by service expectations exists
