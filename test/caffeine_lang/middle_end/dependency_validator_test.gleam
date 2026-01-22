import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/middle_end/dependency_validator
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import test_helpers

// Helper to create a minimal SLO IR (no dependency relations)
fn make_slo_ir(
  org: String,
  team: String,
  service: String,
  name: String,
) -> semantic_analyzer.IntermediateRepresentation {
  semantic_analyzer.IntermediateRepresentation(
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: name,
      org_name: org,
      service_name: service,
      blueprint_name: "test_blueprint",
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: org <> "_" <> service <> "_" <> name,
    artifact_refs: ["SLO"],
    values: [
      helpers.ValueTuple(
        "vendor",
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        dynamic.float(99.9),
      ),
    ],
    vendor: option.Some(vendor.Datadog),
  )
}

// Helper to create an IR with dependency relations
fn make_ir_with_dependencies(
  org: String,
  team: String,
  service: String,
  name: String,
  hard_deps: List(String),
  soft_deps: List(String),
) -> semantic_analyzer.IntermediateRepresentation {
  let relations_value =
    dynamic.properties([
      #(dynamic.string("hard"), dynamic.list(hard_deps |> list.map(dynamic.string))),
      #(dynamic.string("soft"), dynamic.list(soft_deps |> list.map(dynamic.string))),
    ])

  semantic_analyzer.IntermediateRepresentation(
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: name,
      org_name: org,
      service_name: service,
      blueprint_name: "test_blueprint",
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: org <> "_" <> service <> "_" <> name,
    artifact_refs: ["SLO", "DependencyRelations"],
    values: [
      helpers.ValueTuple(
        "vendor",
        accepted_types.PrimitiveType(primitive_types.String),
        dynamic.string("datadog"),
      ),
      helpers.ValueTuple(
        "threshold",
        accepted_types.PrimitiveType(primitive_types.NumericType(
          numeric_types.Float,
        )),
        dynamic.float(99.9),
      ),
      helpers.ValueTuple(
        "relations",
        accepted_types.CollectionType(collection_types.Dict(
          accepted_types.PrimitiveType(primitive_types.String),
          accepted_types.CollectionType(
            collection_types.List(accepted_types.PrimitiveType(
              primitive_types.String,
            )),
          ),
        )),
        relations_value,
      ),
    ],
    vendor: option.Some(vendor.Datadog),
  )
}

// ==== validate_dependency_relations ====
// * ✅ happy path - no IRs with dependency relations (nothing to validate)
// * ✅ happy path - IR with valid dependency references (all targets exist)
// * ✅ happy path - multiple IRs with cross-references
// * ✅ sad path - dependency target does not exist
// * ✅ sad path - dependency target has invalid format (not 4 parts)
// * ✅ sad path - self-reference (IR depends on itself)
// * ✅ sad path - multiple invalid dependencies (all reported)
pub fn validate_dependency_relations_test() {
  // Happy path: no IRs with dependency relations
  [
    #(
      [
        make_slo_ir("acme", "platform", "auth", "login_slo"),
        make_slo_ir("acme", "platform", "db", "query_slo"),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    case dependency_validator.validate_dependency_relations(irs) {
      Ok(_) -> Ok(True)
      Error(err) -> Error(err)
    }
  })

  // Happy path: valid dependency references
  [
    #(
      [
        make_slo_ir("acme", "platform", "db", "availability_slo"),
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["acme.platform.db.availability_slo"],
          [],
        ),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    case dependency_validator.validate_dependency_relations(irs) {
      Ok(_) -> Ok(True)
      Error(err) -> Error(err)
    }
  })

  // Happy path: multiple IRs with cross-references
  [
    #(
      [
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["acme.infra.db.query_slo"],
          ["acme.observability.logging.ingestion_slo"],
        ),
        make_slo_ir("acme", "infra", "db", "query_slo"),
        make_slo_ir("acme", "observability", "logging", "ingestion_slo"),
      ],
      Ok(True),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(irs) {
    case dependency_validator.validate_dependency_relations(irs) {
      Ok(_) -> Ok(True)
      Error(err) -> Error(err)
    }
  })

  // Sad path: dependency target does not exist
  [
    #(
      [
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["acme.platform.db.nonexistent_slo"],
          [],
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
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["invalid_format"],
          [],
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
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["acme.platform.auth.login_slo"],
          [],
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
        make_ir_with_dependencies(
          "acme",
          "platform",
          "auth",
          "login_slo",
          ["bad_format", "also.bad"],
          [],
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
}

// ==== parse_dependency_path ====
// * ✅ happy path - valid 4-part path
// * ✅ sad path - too few parts
// * ✅ sad path - too many parts
// * ✅ sad path - empty string
pub fn parse_dependency_path_test() {
  [
    // Valid 4-part path
    #("acme.platform.auth.login_slo", Ok(#("acme", "platform", "auth", "login_slo"))),
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

// ==== build_expectation_index ====
// * ✅ builds index from list of IRs
pub fn build_expectation_index_test() {
  let irs = [
    make_slo_ir("acme", "platform", "auth", "login_slo"),
    make_slo_ir("acme", "infra", "db", "query_slo"),
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
