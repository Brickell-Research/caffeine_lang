import caffeine_lang/analysis/dependency_validator
import caffeine_lang/analysis/semantic_analyzer.{type IntermediateRepresentation}
import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import gleam/dict
import ir_test_helpers
import test_helpers

/// Wraps validate_dependency_relations to map Ok(irs) to Ok(True) for test assertions.
fn validate_ok(
  irs: List(IntermediateRepresentation),
) -> Result(Bool, errors.CompilationError) {
  case dependency_validator.validate_dependency_relations(irs) {
    Ok(_) -> Ok(True)
    Error(err) -> Error(err)
  }
}

// ==== validate_dependency_relations ====
// * ✅ happy path - no IRs with dependency relations (nothing to validate)
// * ✅ happy path - IR with valid dependency references (all targets exist)
// * ✅ happy path - multiple IRs with cross-references
// * ✅ sad path - dependency target does not exist
// * ✅ sad path - dependency target has invalid format (not 4 parts)
// * ✅ sad path - self-reference (IR depends on itself)
// * ✅ sad path - multiple invalid dependencies (all reported)
// * ✅ happy path - same dependency in both hard and soft (allowed)
// * ✅ sad path - duplicate dependency within same relation type
pub fn validate_dependency_relations_test() {
  let default_threshold = helpers.default_threshold_percentage

  // Happy path: no IRs with dependency relations
  [
    #(
      [
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "auth",
          "login_slo",
          threshold: default_threshold,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "db",
          "query_slo",
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Happy path: valid dependency references
  [
    #(
      [
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "db",
          "availability_slo",
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.platform.db.availability_slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Happy path: multiple IRs with cross-references
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: ["acme.observability.logging.ingestion_slo"],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: default_threshold,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "observability",
          "logging",
          "ingestion_slo",
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Sad path: dependency target does not exist
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.platform.db.nonexistent_slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Invalid dependency reference 'acme.platform.db.nonexistent_slo' in 'acme.platform.auth.login_slo': target does not exist",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Sad path: invalid format (not 4 parts)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["invalid_format"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Invalid dependency reference 'invalid_format' in 'acme.platform.auth.login_slo': expected format 'org.team.service.name'",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Sad path: self-reference
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.platform.auth.login_slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Invalid dependency reference 'acme.platform.auth.login_slo' in 'acme.platform.auth.login_slo': self-reference not allowed",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Sad path: multiple invalid dependencies (first error reported)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["bad_format", "also.bad"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Invalid dependency reference 'bad_format' in 'acme.platform.auth.login_slo': expected format 'org.team.service.name'",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Sad path: duplicate dependency within same relation type
  [
    #(
      [
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "db",
          "availability_slo",
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [
            "acme.platform.db.availability_slo",
            "acme.platform.db.availability_slo",
          ],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Duplicate dependency reference 'acme.platform.db.availability_slo' in 'acme.platform.auth.login_slo'",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Happy path: same dependency in both hard and soft (allowed)
  [
    #(
      [
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "db",
          "availability_slo",
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.platform.db.availability_slo"],
          soft_deps: ["acme.platform.db.availability_slo"],
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)
}

// ==== parse_dependency_path ====
// * ✅ happy path - valid 4-part path
// * ✅ sad path - too few parts
// * ✅ sad path - too many parts
// * ✅ sad path - empty string
pub fn parse_dependency_path_test() {
  [
    // Valid 4-part path
    #(
      "acme.platform.auth.login_slo",
      Ok(#("acme", "platform", "auth", "login_slo")),
    ),
    // Too few parts
    #("acme.platform.auth", Error(Nil)),
    #("acme.platform", Error(Nil)),
    #("acme", Error(Nil)),
    // Too many parts
    #("acme.platform.auth.login.extra", Error(Nil)),
    // Empty string
    #("", Error(Nil)),
    // Empty parts
    #("acme..auth.login", Error(Nil)),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    dependency_validator.parse_dependency_path(input)
  })
}

// ==== detect_cycles (via validate_dependency_relations) ====
// * ✅ no cycle - linear chain A -> B -> C
// * ✅ no cycle - diamond A -> B, A -> C, B -> D, C -> D
// * ❌ 2-node cycle: A -> B -> A
// * ❌ 3-node cycle: A -> B -> C -> A
// * ❌ cycle across relation types: A ->hard B, B ->soft A
pub fn detect_cycles_test() {
  let default_threshold = helpers.default_threshold_percentage

  // No cycle: linear chain A -> B -> C
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "a",
          "slo",
          hard_deps: ["acme.platform.b.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "b",
          "slo",
          hard_deps: ["acme.platform.c.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "c",
          "slo",
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // No cycle: diamond A -> B, A -> C, B -> D, C -> D
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "a",
          "slo",
          hard_deps: ["acme.platform.b.slo", "acme.platform.c.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "b",
          "slo",
          hard_deps: ["acme.platform.d.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "c",
          "slo",
          hard_deps: ["acme.platform.d.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "platform",
          "d",
          "slo",
          threshold: default_threshold,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // 2-node cycle: A -> B -> A
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "a",
          "slo",
          hard_deps: ["acme.platform.b.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "b",
          "slo",
          hard_deps: ["acme.platform.a.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Circular dependency detected: acme.platform.a.slo -> acme.platform.b.slo -> acme.platform.a.slo",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // 3-node cycle: A -> B -> C -> A
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "a",
          "slo",
          hard_deps: ["acme.platform.b.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "b",
          "slo",
          hard_deps: ["acme.platform.c.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "c",
          "slo",
          hard_deps: ["acme.platform.a.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Circular dependency detected: acme.platform.a.slo -> acme.platform.b.slo -> acme.platform.c.slo -> acme.platform.a.slo",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Cycle across relation types: A ->hard B, B ->soft A
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "a",
          "slo",
          hard_deps: ["acme.platform.b.slo"],
          soft_deps: [],
          threshold: default_threshold,
        ),
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "b",
          "slo",
          hard_deps: [],
          soft_deps: ["acme.platform.a.slo"],
          threshold: default_threshold,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Circular dependency detected: acme.platform.a.slo -> acme.platform.b.slo -> acme.platform.a.slo",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })
}

// ==== validate_hard_dependency_thresholds (via validate_dependency_relations) ====
// * ✅ source threshold <= target threshold (99.9 <= 99.99)
// * ✅ equal thresholds (99.9 == 99.9)
// * ❌ source threshold > target threshold (99.99 > 99.9)
// * ✅ soft dependencies skip threshold check
// * ✅ skip when source has no SLO artifact
// * ✅ skip when target has no SLO artifact
pub fn validate_hard_dependency_thresholds_test() {
  // Source threshold <= target threshold (99.9 <= 99.99)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: [],
          threshold: 99.9,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.99,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Equal thresholds (99.9 == 99.9)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: [],
          threshold: 99.9,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.9,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Source threshold > target threshold (99.99 > 99.9) - ERROR
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: [],
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.9,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Hard dependency threshold violation: 'acme.platform.auth.login_slo' (threshold: 99.99) cannot exceed its hard dependency 'acme.infra.db.query_slo' (threshold: 99.9)",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Soft dependencies skip threshold check
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [],
          soft_deps: ["acme.infra.db.query_slo"],
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.9,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Skip when source has no SLO artifact
  [
    #(
      [
        ir_test_helpers.make_deps_only_ir(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: [],
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.9,
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // Skip when target has no SLO artifact
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: ["acme.infra.db.query_slo"],
          soft_deps: [],
          threshold: 99.99,
        ),
        ir_test_helpers.make_deps_only_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          hard_deps: [],
          soft_deps: [],
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)
}

// ==== build_expectation_index ====
// * ✅ builds index from list of IRs
pub fn build_expectation_index_test() {
  let default_threshold = helpers.default_threshold_percentage
  let irs = [
    ir_test_helpers.make_slo_ir(
      "acme",
      "platform",
      "auth",
      "login_slo",
      threshold: default_threshold,
    ),
    ir_test_helpers.make_slo_ir(
      "acme",
      "infra",
      "db",
      "query_slo",
      threshold: default_threshold,
    ),
  ]

  let index = dependency_validator.build_expectation_index(irs)

  // Test that expected paths exist - use executor_2 for path + index
  [
    #("acme.platform.auth.login_slo", index, True),
    #("acme.infra.db.query_slo", index, True),
    #("acme.platform.auth.other_slo", index, False),
    #("nonexistent.path.here.slo", index, False),
  ]
  |> test_helpers.array_based_test_executor_2(fn(path, idx) {
    case dict.get(idx, path) {
      Ok(_) -> True
      Error(_) -> False
    }
  })
}
