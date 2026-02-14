import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/linker/blueprints
import caffeine_lang/linker/expectations
import caffeine_lang/linker/ir_builder
import caffeine_lang/standard_library/artifacts as stdlib_artifacts
import caffeine_lang/types
import caffeine_lang/value.{type Value}
import gleam/dict
import gleam/list
import gleam/option
import gleam/set
import gleam/string
import gleeunit/should
import test_helpers

/// Standard reserved labels set for tests.
fn test_reserved_labels() {
  ir_builder.reserved_labels_from_artifacts(stdlib_artifacts.standard_library())
}

// ==== extract_path_prefix ====
// * ✅ standard path with .json extension
// * ✅ path without enough segments returns unknown
pub fn extract_path_prefix_test() {
  [
    #("org/team/service.json", #("org", "team", "service")),
    #("examples/acme/platform_team/auth.json", #(
      "acme",
      "platform_team",
      "auth",
    )),
    #("org/team", #("unknown", "unknown", "unknown")),
    #("single", #("unknown", "unknown", "unknown")),
  ]
  |> test_helpers.array_based_test_executor_1(helpers.extract_path_prefix)
}

// ==== build_all ====
// * ✅ empty list returns empty list
// * ✅ single expectation builds correct IR
// * ✅ multiple expectations from single file
// * ✅ multiple files flattened into single list
// * ✅ optional params not provided get nil value
// * ✅ defaulted params not provided get nil value
// * ✅ refinement type with defaulted inner not provided gets nil value
// * ✅ blueprint inputs merged with expectation inputs
// * ✅ misc metadata populated from string values (excluding filtered keys)
pub fn build_all_test() {
  // empty list returns empty list
  ir_builder.build_all([], reserved_labels: test_reserved_labels())
  |> should.equal(Ok([]))

  // single expectation builds correct IR
  {
    let blueprint =
      make_blueprint("test_blueprint", [#("threshold", FloatType)])
    let expectation =
      make_expectation("my_test", [#("threshold", value.FloatValue(99.9))])

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/service.json")],
        reserved_labels: test_reserved_labels(),
      )
    ir.metadata.friendly_label |> should.equal("my_test")
    ir.metadata.org_name |> should.equal("org")
    ir.metadata.team_name |> should.equal("team")
    ir.metadata.service_name |> should.equal("service")
    ir.metadata.blueprint_name |> should.equal("test_blueprint")
    ir.unique_identifier |> should.equal("org_service_my_test")
    ir.artifact_refs |> should.equal([SLO])
    ir.vendor |> should.equal(option.Some(vendor.Datadog))
    // Check values contain expected tuples (order-independent)
    ir.values
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
    |> should.equal([
      helpers.ValueTuple(
        label: "threshold",
        typ: types.PrimitiveType(types.NumericType(types.Float)),
        value: value.FloatValue(99.9),
      ),
      helpers.ValueTuple(
        label: "vendor",
        typ: types.PrimitiveType(types.String),
        value: value.StringValue(constants.vendor_datadog),
      ),
    ])
  }

  // multiple expectations from single file
  {
    let blueprint =
      make_blueprint("test_blueprint", [
        #("threshold", FloatType),
        #("value", FloatType),
      ])
    let exp1 =
      make_expectation("first", [
        #("threshold", value.FloatValue(99.9)),
        #("value", value.FloatValue(1.0)),
      ])
    let exp2 =
      make_expectation("second", [
        #("threshold", value.FloatValue(99.9)),
        #("value", value.FloatValue(2.0)),
      ])

    let assert Ok(result) =
      ir_builder.build_all(
        [#([#(exp1, blueprint), #(exp2, blueprint)], "org/team/service.json")],
        reserved_labels: test_reserved_labels(),
      )

    result |> list.length |> should.equal(2)
    let assert [ir1, ir2] = result
    ir1.metadata.friendly_label |> should.equal("first")
    ir2.metadata.friendly_label |> should.equal("second")
  }

  // multiple files flattened into single list
  {
    let blueprint =
      make_blueprint("test_blueprint", [
        #("threshold", FloatType),
        #("id", FloatType),
      ])
    let exp1 =
      make_expectation("from_file1", [
        #("threshold", value.FloatValue(99.9)),
        #("id", value.FloatValue(1.0)),
      ])
    let exp2 =
      make_expectation("from_file2", [
        #("threshold", value.FloatValue(99.9)),
        #("id", value.FloatValue(2.0)),
      ])

    let assert Ok(result) =
      ir_builder.build_all(
        [
          #([#(exp1, blueprint)], "org/team/file1.json"),
          #([#(exp2, blueprint)], "org/team/file2.json"),
        ],
        reserved_labels: test_reserved_labels(),
      )

    result |> list.length |> should.equal(2)
    let assert [ir1, ir2] = result
    ir1.metadata.service_name |> should.equal("file1")
    ir2.metadata.service_name |> should.equal("file2")
  }

  // optional params not provided get nil value
  {
    let blueprint =
      blueprints.Blueprint(
        name: "test_blueprint",
        artifact_refs: [SLO],
        params: dict.from_list([
          #("vendor", types.PrimitiveType(types.String)),
          #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          #("required", types.PrimitiveType(types.NumericType(types.Float))),
          #(
            "optional_field",
            types.ModifierType(
              types.Optional(types.PrimitiveType(types.String)),
            ),
          ),
        ]),
        inputs: dict.from_list([
          #("vendor", value.StringValue(constants.vendor_datadog)),
          #("threshold", value.FloatValue(99.9)),
        ]),
      )
    let expectation =
      make_expectation("my_test", [#("required", value.FloatValue(1.0))])

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/svc.json")],
        reserved_labels: test_reserved_labels(),
      )

    ir.values
    |> list.filter(fn(vt) { vt.label != "vendor" && vt.label != "threshold" })
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
    |> should.equal([
      helpers.ValueTuple(
        label: "optional_field",
        typ: types.ModifierType(
          types.Optional(types.PrimitiveType(types.String)),
        ),
        value: value.NilValue,
      ),
      helpers.ValueTuple(
        label: "required",
        typ: types.PrimitiveType(types.NumericType(types.Float)),
        value: value.FloatValue(1.0),
      ),
    ])
  }

  // defaulted params not provided get nil value
  {
    let blueprint =
      blueprints.Blueprint(
        name: "test_blueprint",
        artifact_refs: [SLO],
        params: dict.from_list([
          #("vendor", types.PrimitiveType(types.String)),
          #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          #("required", types.PrimitiveType(types.NumericType(types.Float))),
          #(
            "defaulted_field",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "default_value",
            )),
          ),
        ]),
        inputs: dict.from_list([
          #("vendor", value.StringValue(constants.vendor_datadog)),
          #("threshold", value.FloatValue(99.9)),
        ]),
      )
    let expectation =
      make_expectation("my_test", [#("required", value.FloatValue(1.0))])

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/svc.json")],
        reserved_labels: test_reserved_labels(),
      )

    ir.values
    |> list.filter(fn(vt) { vt.label != "vendor" && vt.label != "threshold" })
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
    |> should.equal([
      helpers.ValueTuple(
        label: "defaulted_field",
        typ: types.ModifierType(types.Defaulted(
          types.PrimitiveType(types.String),
          "default_value",
        )),
        value: value.NilValue,
      ),
      helpers.ValueTuple(
        label: "required",
        typ: types.PrimitiveType(types.NumericType(types.Float)),
        value: value.FloatValue(1.0),
      ),
    ])
  }

  // refinement type with defaulted inner not provided gets nil value
  {
    let blueprint =
      blueprints.Blueprint(
        name: "test_blueprint",
        artifact_refs: [SLO],
        params: dict.from_list([
          #("vendor", types.PrimitiveType(types.String)),
          #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          #("required", types.PrimitiveType(types.NumericType(types.Float))),
          #(
            "environment",
            types.RefinementType(types.OneOf(
              types.ModifierType(types.Defaulted(
                types.PrimitiveType(types.String),
                "production",
              )),
              set.from_list(["production", "staging"]),
            )),
          ),
        ]),
        inputs: dict.from_list([
          #("vendor", value.StringValue(constants.vendor_datadog)),
          #("threshold", value.FloatValue(99.9)),
        ]),
      )
    let expectation =
      make_expectation("my_test", [#("required", value.FloatValue(1.0))])

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/svc.json")],
        reserved_labels: test_reserved_labels(),
      )

    ir.values
    |> list.filter(fn(vt) { vt.label != "vendor" && vt.label != "threshold" })
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
    |> should.equal([
      helpers.ValueTuple(
        label: "environment",
        typ: types.RefinementType(types.OneOf(
          types.ModifierType(types.Defaulted(
            types.PrimitiveType(types.String),
            "production",
          )),
          set.from_list(["production", "staging"]),
        )),
        value: value.NilValue,
      ),
      helpers.ValueTuple(
        label: "required",
        typ: types.PrimitiveType(types.NumericType(types.Float)),
        value: value.FloatValue(1.0),
      ),
    ])
  }

  // blueprint inputs merged with expectation inputs
  {
    let blueprint =
      blueprints.Blueprint(
        name: "test_blueprint",
        artifact_refs: [SLO],
        params: dict.from_list([
          #("vendor", types.PrimitiveType(types.String)),
          #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
          #("from_blueprint", types.PrimitiveType(types.String)),
          #(
            "from_expectation",
            types.PrimitiveType(types.NumericType(types.Float)),
          ),
        ]),
        inputs: dict.from_list([
          #("vendor", value.StringValue(constants.vendor_datadog)),
          #("threshold", value.FloatValue(99.9)),
          #("from_blueprint", value.StringValue("blueprint_value")),
        ]),
      )
    let expectation =
      make_expectation("my_test", [
        #("from_expectation", value.FloatValue(42.0)),
      ])

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/svc.json")],
        reserved_labels: test_reserved_labels(),
      )

    ir.values
    |> list.filter(fn(vt) { vt.label != "vendor" && vt.label != "threshold" })
    |> list.sort(fn(a, b) { string.compare(a.label, b.label) })
    |> should.equal([
      helpers.ValueTuple(
        label: "from_blueprint",
        typ: types.PrimitiveType(types.String),
        value: value.StringValue("blueprint_value"),
      ),
      helpers.ValueTuple(
        label: "from_expectation",
        typ: types.PrimitiveType(types.NumericType(types.Float)),
        value: value.FloatValue(42.0),
      ),
    ])
  }

  // misc metadata populated from string values (excluding filtered keys)
  {
    let blueprint =
      blueprints.Blueprint(
        name: "test_blueprint",
        artifact_refs: [SLO],
        params: dict.from_list([
          #("vendor", types.PrimitiveType(types.String)),
          #("env", types.PrimitiveType(types.String)),
          #("region", types.PrimitiveType(types.String)),
          #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
        ]),
        inputs: dict.from_list([
          #("vendor", value.StringValue(constants.vendor_datadog)),
        ]),
      )
    let expectation =
      expectations.Expectation(
        name: "my_test",
        blueprint_ref: "test_blueprint",
        inputs: dict.from_list([
          #("env", value.StringValue("production")),
          #("region", value.StringValue("us-east-1")),
          #("threshold", value.FloatValue(99.9)),
        ]),
      )

    let assert Ok([ir]) =
      ir_builder.build_all(
        [#([#(expectation, blueprint)], "org/team/svc.json")],
        reserved_labels: test_reserved_labels(),
      )

    // misc should contain string values but NOT threshold or non-strings
    ir.metadata.misc
    |> should.equal(
      dict.from_list([
        #("env", ["production"]),
        #("region", ["us-east-1"]),
        #("vendor", [constants.vendor_datadog]),
      ]),
    )
  }
}

// ==== build_all - list-type params produce multiple values in misc ====
pub fn build_all_list_misc_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_refs: [SLO],
      params: dict.from_list([
        #("vendor", types.PrimitiveType(types.String)),
        #(
          "job_name",
          types.CollectionType(types.List(types.PrimitiveType(types.String))),
        ),
        #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
      ]),
      inputs: dict.from_list([
        #("vendor", value.StringValue(constants.vendor_datadog)),
      ]),
    )
  let expectation =
    expectations.Expectation(
      name: "my_test",
      blueprint_ref: "test_blueprint",
      inputs: dict.from_list([
        #(
          "job_name",
          value.ListValue([
            value.StringValue("deploy-prod"),
            value.StringValue("deploy-demo"),
          ]),
        ),
        #("threshold", value.FloatValue(99.9)),
      ]),
    )

  let assert Ok([ir]) =
    ir_builder.build_all(
      [#([#(expectation, blueprint)], "org/team/svc.json")],
      reserved_labels: test_reserved_labels(),
    )

  ir.metadata.misc
  |> should.equal(
    dict.from_list([
      #("job_name", ["deploy-prod", "deploy-demo"]),
      #("vendor", [constants.vendor_datadog]),
    ]),
  )
}

// ==== build_all - Optional(None) excluded from misc ====
pub fn build_all_optional_none_misc_test() {
  let blueprint =
    blueprints.Blueprint(
      name: "test_blueprint",
      artifact_refs: [SLO],
      params: dict.from_list([
        #("vendor", types.PrimitiveType(types.String)),
        #("threshold", types.PrimitiveType(types.NumericType(types.Float))),
        #(
          "env",
          types.ModifierType(types.Optional(types.PrimitiveType(types.String))),
        ),
      ]),
      inputs: dict.from_list([
        #("vendor", value.StringValue(constants.vendor_datadog)),
      ]),
    )
  let expectation =
    make_expectation("my_test", [#("threshold", value.FloatValue(1.0))])

  let assert Ok([ir]) =
    ir_builder.build_all(
      [#([#(expectation, blueprint)], "org/team/svc.json")],
      reserved_labels: test_reserved_labels(),
    )

  // Optional(None) should be excluded from misc (threshold is filtered by label)
  ir.metadata.misc
  |> should.equal(dict.from_list([#("vendor", [constants.vendor_datadog])]))
}

// ==== Helpers ====

type PrimitiveShorthand {
  FloatType
  StringType
}

fn make_blueprint(
  name: String,
  params: List(#(String, PrimitiveShorthand)),
) -> blueprints.Blueprint {
  blueprints.Blueprint(
    name: name,
    artifact_refs: [SLO],
    params: [
      #("vendor", types.PrimitiveType(types.String)),
      ..{
        params
        |> list.map(fn(p) {
          let #(label, typ) = p
          #(
            label,
            types.PrimitiveType(case typ {
              FloatType -> types.NumericType(types.Float)
              StringType -> types.String
            }),
          )
        })
      }
    ]
      |> dict.from_list,
    inputs: dict.from_list([
      #("vendor", value.StringValue(constants.vendor_datadog)),
    ]),
  )
}

fn make_expectation(
  name: String,
  inputs: List(#(String, Value)),
) -> expectations.Expectation {
  expectations.Expectation(
    name: name,
    blueprint_ref: "test_blueprint",
    inputs: dict.from_list(inputs),
  )
}
