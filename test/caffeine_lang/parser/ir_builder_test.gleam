import caffeine_lang/common/accepted_types.{
  Defaulted, Float, ModifierType, Optional, PrimitiveType, String,
}
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/parser/blueprints
import caffeine_lang/parser/expectations
import caffeine_lang/parser/ir_builder
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import test_helpers

// ==== extract_path_prefix ====
// * ✅ standard path with .json extension
// * ✅ path without enough segments returns unknown
pub fn extract_path_prefix_test() {
  [
    #("org/team/service.json", #("org", "team", "service")),
    #("examples/acme/platform_team/auth.json", #("acme", "platform_team", "auth")),
    #("org/team", #("unknown", "unknown", "unknown")),
    #("single", #("unknown", "unknown", "unknown")),
  ]
  |> test_helpers.array_based_test_executor_1(ir_builder.extract_path_prefix)
}

// ==== build_all ====
// * ✅ empty list returns empty list
// * ✅ single expectation builds correct IR
// * ✅ multiple expectations from single file
// * ✅ multiple files flattened into single list
// * ✅ optional params not provided get nil value
// * ✅ defaulted params not provided get nil value
// * ✅ blueprint inputs merged with expectation inputs
// * ✅ misc metadata populated from string values (excluding filtered keys)
pub fn build_all_empty_test() {
  ir_builder.build_all([])
  |> should.equal([])
}

pub fn build_all_single_expectation_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([#("threshold", PrimitiveType(Float))]),
      inputs: dict.from_list([]),
    )

  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("threshold", dynamic.float(99.9))]),
    )

  let result =
    ir_builder.build_all([#([#(expectation, blueprint)], "org/team/service.json")])

  result
  |> should.equal([
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "my_test",
        org_name: "org",
        service_name: "service",
        blueprint_name: "test_blueprint",
        team_name: "team",
        misc: dict.new(),
      ),
      unique_identifier: "org_service_my_test",
      artifact_ref: "TestArtifact",
      values: [
        helpers.ValueTuple(
          label: "threshold",
          typ: PrimitiveType(Float),
          value: dynamic.float(99.9),
        ),
      ],
      vendor: option.None,
    ),
  ])
}

pub fn build_all_multiple_expectations_single_file_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([#("value", PrimitiveType(Float))]),
      inputs: dict.from_list([]),
    )

  let exp1 =
    expectations.Expectation(
      name: "first",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("value", dynamic.float(1.0))]),
    )

  let exp2 =
    expectations.Expectation(
      name: "second",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("value", dynamic.float(2.0))]),
    )

  let result =
    ir_builder.build_all([
      #([#(exp1, blueprint), #(exp2, blueprint)], "org/team/service.json"),
    ])

  result
  |> should.equal([
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "first",
        org_name: "org",
        service_name: "service",
        blueprint_name: "test_blueprint",
        team_name: "team",
        misc: dict.new(),
      ),
      unique_identifier: "org_service_first",
      artifact_ref: "TestArtifact",
      values: [
        helpers.ValueTuple(
          label: "value",
          typ: PrimitiveType(Float),
          value: dynamic.float(1.0),
        ),
      ],
      vendor: option.None,
    ),
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "second",
        org_name: "org",
        service_name: "service",
        blueprint_name: "test_blueprint",
        team_name: "team",
        misc: dict.new(),
      ),
      unique_identifier: "org_service_second",
      artifact_ref: "TestArtifact",
      values: [
        helpers.ValueTuple(
          label: "value",
          typ: PrimitiveType(Float),
          value: dynamic.float(2.0),
        ),
      ],
      vendor: option.None,
    ),
  ])
}

pub fn build_all_multiple_files_flattened_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([#("id", PrimitiveType(Float))]),
      inputs: dict.from_list([]),
    )

  let exp1 =
    expectations.Expectation(
      name: "from_file1",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("id", dynamic.float(1.0))]),
    )

  let exp2 =
    expectations.Expectation(
      name: "from_file2",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("id", dynamic.float(2.0))]),
    )

  let result =
    ir_builder.build_all([
      #([#(exp1, blueprint)], "org/team/file1.json"),
      #([#(exp2, blueprint)], "org/team/file2.json"),
    ])

  // Should have 2 IRs from 2 different files
  result
  |> should.equal([
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "from_file1",
        org_name: "org",
        service_name: "file1",
        blueprint_name: "test_blueprint",
        team_name: "team",
        misc: dict.new(),
      ),
      unique_identifier: "org_file1_from_file1",
      artifact_ref: "TestArtifact",
      values: [
        helpers.ValueTuple(
          label: "id",
          typ: PrimitiveType(Float),
          value: dynamic.float(1.0),
        ),
      ],
      vendor: option.None,
    ),
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "from_file2",
        org_name: "org",
        service_name: "file2",
        blueprint_name: "test_blueprint",
        team_name: "team",
        misc: dict.new(),
      ),
      unique_identifier: "org_file2_from_file2",
      artifact_ref: "TestArtifact",
      values: [
        helpers.ValueTuple(
          label: "id",
          typ: PrimitiveType(Float),
          value: dynamic.float(2.0),
        ),
      ],
      vendor: option.None,
    ),
  ])
}

pub fn build_all_optional_params_get_nil_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([
        #("required", PrimitiveType(Float)),
        #("optional_field", ModifierType(Optional(PrimitiveType(String)))),
      ]),
      inputs: dict.from_list([]),
    )

  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("required", dynamic.float(1.0))]),
    )

  let result =
    ir_builder.build_all([#([#(expectation, blueprint)], "org/team/svc.json")])

  let assert [ir] = result

  // Should have both required and optional in values
  ir.values
  |> should.equal([
    helpers.ValueTuple(
      label: "required",
      typ: PrimitiveType(Float),
      value: dynamic.float(1.0),
    ),
    helpers.ValueTuple(
      label: "optional_field",
      typ: ModifierType(Optional(PrimitiveType(String))),
      value: dynamic.nil(),
    ),
  ])
}

pub fn build_all_defaulted_params_get_nil_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([
        #("required", PrimitiveType(Float)),
        #("defaulted_field", ModifierType(Defaulted(PrimitiveType(String), "default_value"))),
      ]),
      inputs: dict.from_list([]),
    )

  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("required", dynamic.float(1.0))]),
    )

  let result =
    ir_builder.build_all([#([#(expectation, blueprint)], "org/team/svc.json")])

  let assert [ir] = result

  // Should have both required and defaulted in values
  ir.values
  |> should.equal([
    helpers.ValueTuple(
      label: "required",
      typ: PrimitiveType(Float),
      value: dynamic.float(1.0),
    ),
    helpers.ValueTuple(
      label: "defaulted_field",
      typ: ModifierType(Defaulted(PrimitiveType(String), "default_value")),
      value: dynamic.nil(),
    ),
  ])
}

pub fn build_all_blueprint_inputs_merged_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([
        #("from_blueprint", PrimitiveType(String)),
        #("from_expectation", PrimitiveType(Float)),
      ]),
      inputs: dict.from_list([#("from_blueprint", dynamic.string("blueprint_value"))]),
    )

  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([#("from_expectation", dynamic.float(42.0))]),
    )

  let result =
    ir_builder.build_all([#([#(expectation, blueprint)], "org/team/svc.json")])

  let assert [ir] = result

  // Should have values from both blueprint and expectation inputs
  // Sort by label for deterministic comparison across targets
  ir.values
  |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
  |> should.equal([
    helpers.ValueTuple(
      label: "from_blueprint",
      typ: PrimitiveType(String),
      value: dynamic.string("blueprint_value"),
    ),
    helpers.ValueTuple(
      label: "from_expectation",
      typ: PrimitiveType(Float),
      value: dynamic.float(42.0),
    ),
  ])
}

pub fn build_all_misc_metadata_from_string_values_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_ref: "TestArtifact",
      params: dict.from_list([
        #("env", PrimitiveType(String)),
        #("region", PrimitiveType(String)),
        #("threshold", PrimitiveType(Float)),
      ]),
      inputs: dict.from_list([]),
    )

  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([
        #("env", dynamic.string("production")),
        #("region", dynamic.string("us-east-1")),
        #("threshold", dynamic.float(99.9)),
      ]),
    )

  let result =
    ir_builder.build_all([#([#(expectation, blueprint)], "org/team/svc.json")])

  let assert [ir] = result

  // misc should contain string values but NOT threshold (filtered) or non-strings
  ir.metadata.misc
  |> should.equal(
    dict.from_list([#("env", "production"), #("region", "us-east-1")]),
  )
}
