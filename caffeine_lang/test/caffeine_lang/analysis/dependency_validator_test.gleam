import caffeine_lang/analysis/dependency_validator
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/linker/ir.{type IntermediateRepresentation}
import gleam/dict
import ir_test_helpers
import test_helpers

/// Wraps validate_dependency_relations to map Ok(irs) to Ok(Nil) for test assertions.
fn validate_ok(
  irs: List(IntermediateRepresentation),
) -> Result(Nil, errors.CompilationError) {
  case dependency_validator.validate_dependency_relations(irs) {
    Ok(_) -> Ok(Nil)
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
      Ok(Nil),
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
      Ok(Nil),
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
      Ok(Nil),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
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
      Ok(Nil),
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
      Ok(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // No cycle: diamond A -> B, A -> C, B -> D, C -> D
  // A's threshold must be below composite ceiling of B and C (~99.8001)
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
          threshold: 99.0,
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
      Ok(Nil),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
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
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })
}

// ==== validate_hard_dependency_thresholds (via validate_dependency_relations) ====
// * ✅ source threshold <= single dep threshold (99.9 <= 99.99)
// * ✅ equal thresholds with single dep (99.9 == 99.9)
// * ❌ source threshold > single dep threshold (99.99 > 99.9)
// * ✅ soft dependencies skip threshold check
// * ✅ skip when source has no SLO artifact
// * ✅ skip when target has no SLO artifact
// * ✅ 2 hard deps, source below composite ceiling
// * ❌ 2 hard deps at 99.99%, source at 99.99% exceeds composite ceiling
// * ❌ 3 hard deps, source above composite ceiling
// * ✅ mix of hard deps with and without SLO (only SLO deps count)
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
      Ok(Nil),
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
      Ok(Nil),
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
        msg: "Composite hard dependency threshold violation: 'acme.platform.auth.login_slo' (threshold: 99.99) exceeds the composite availability ceiling of 99.9 from its hard dependencies: 'acme.infra.db.query_slo' (99.9)",
        context: errors.empty_context(),
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
      Ok(Nil),
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
      Ok(Nil),
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
      Ok(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // 2 hard deps, source below composite ceiling
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [
            "acme.infra.db.query_slo",
            "acme.infra.cache.redis_slo",
          ],
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
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "cache",
          "redis_slo",
          threshold: 99.99,
        ),
      ],
      Ok(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(validate_ok)

  // 2 hard deps at 99.99%, source at 99.99% exceeds composite ceiling (~99.98)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [
            "acme.infra.db.query_slo",
            "acme.infra.cache.redis_slo",
          ],
          soft_deps: [],
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "cache",
          "redis_slo",
          threshold: 99.99,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Composite hard dependency threshold violation: 'acme.platform.auth.login_slo' (threshold: 99.99) exceeds the composite availability ceiling of 99.98000099999999 from its hard dependencies: 'acme.infra.db.query_slo' (99.99), 'acme.infra.cache.redis_slo' (99.99)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // 3 hard deps at 99.99%, source at 99.98% exceeds composite ceiling (~99.97)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [
            "acme.infra.db.query_slo",
            "acme.infra.cache.redis_slo",
            "acme.infra.queue.rabbit_slo",
          ],
          soft_deps: [],
          threshold: 99.98,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "db",
          "query_slo",
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "cache",
          "redis_slo",
          threshold: 99.99,
        ),
        ir_test_helpers.make_slo_ir(
          "acme",
          "infra",
          "queue",
          "rabbit_slo",
          threshold: 99.99,
        ),
      ],
      Error(errors.SemanticAnalysisDependencyValidationError(
        msg: "Composite hard dependency threshold violation: 'acme.platform.auth.login_slo' (threshold: 99.98) exceeds the composite availability ceiling of 99.97000299989998 from its hard dependencies: 'acme.infra.db.query_slo' (99.99), 'acme.infra.cache.redis_slo' (99.99), 'acme.infra.queue.rabbit_slo' (99.99)",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    dependency_validator.validate_dependency_relations(irs)
  })

  // Mix of hard deps with and without SLO (only SLO deps count in composite)
  [
    #(
      [
        ir_test_helpers.make_ir_with_deps(
          "acme",
          "platform",
          "auth",
          "login_slo",
          hard_deps: [
            "acme.infra.db.query_slo",
            "acme.infra.cache.redis_slo",
          ],
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
        ir_test_helpers.make_deps_only_ir(
          "acme",
          "infra",
          "cache",
          "redis_slo",
          hard_deps: [],
          soft_deps: [],
        ),
      ],
      Ok(Nil),
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
