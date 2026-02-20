import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/honeycomb
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/linker/ir
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import ir_test_helpers
import terra_madre/terraform
import test_helpers

// ==== Helpers ====

fn make_honeycomb_ir(
  friendly_label: String,
  unique_identifier: String,
  org: String,
  team: String,
  service: String,
  blueprint: String,
  threshold: Float,
  window_in_days: Int,
  evaluation: String,
  indicators: List(#(String, String)),
) -> ir.IntermediateRepresentation {
  ir_test_helpers.make_vendor_slo_ir(
    friendly_label,
    unique_identifier,
    org,
    team,
    service,
    blueprint,
    threshold,
    window_in_days,
    evaluation,
    indicators,
    constants.vendor_honeycomb,
    vendor.Honeycomb,
  )
}

// ==== terraform_settings ====
// * ✅ includes honeycombio provider requirement
// * ✅ version constraint is ~> 0.31
pub fn terraform_settings_test() {
  let settings = honeycomb.terraform_settings()

  // Check that honeycombio provider is required
  dict.get(settings.required_providers, "honeycombio")
  |> should.be_ok

  // Check version constraint
  let assert Ok(provider_req) =
    dict.get(settings.required_providers, "honeycombio")
  provider_req.source |> should.equal("honeycombio/honeycombio")
  provider_req.version |> should.equal(option.Some("~> 0.31"))
}

// ==== provider ====
// * ✅ provider name is honeycombio
// * ✅ uses variable reference for api_key
// * ✅ does not have app_key (unlike Datadog)
pub fn provider_test() {
  let provider = honeycomb.provider()

  provider.name |> should.equal("honeycombio")
  provider.alias |> should.equal(option.None)

  // Check that api_key attribute exists
  dict.get(provider.attributes, "api_key") |> should.be_ok

  // Honeycomb does not have app_key
  dict.get(provider.attributes, "app_key") |> should.be_error
}

// ==== variables ====
// * ✅ includes honeycomb_api_key variable (sensitive)
// * ✅ includes honeycomb_dataset variable (not sensitive)
pub fn variables_test() {
  let vars = honeycomb.variables()

  // Should have 2 variables
  list.length(vars) |> should.equal(2)

  // Find api_key variable
  let api_key_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "honeycomb_api_key" })
  api_key_var |> should.be_ok
  let assert Ok(api_key) = api_key_var
  api_key.sensitive |> should.equal(option.Some(True))
  api_key.description |> should.equal(option.Some("Honeycomb API key"))

  // Find dataset variable (not sensitive)
  let dataset_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "honeycomb_dataset" })
  dataset_var |> should.be_ok
  let assert Ok(dataset) = dataset_var
  dataset.sensitive |> should.equal(option.None)
  dataset.description |> should.equal(option.Some("Honeycomb dataset slug"))
}

// ==== generate_terraform ====
// * ✅ simple SLO with single indicator
pub fn generate_terraform_test() {
  [
    // simple SLO with single indicator
    #(
      [
        make_honeycomb_ir(
          "API Success Rate",
          "acme_payments_api_success_rate",
          "acme",
          "platform",
          "payments",
          "trace_availability",
          99.5,
          14,
          "sli",
          [#("sli", "LT($\"status_code\", 500)")],
        ),
      ],
      "honeycomb_simple_slo",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_name) = pair
    let expected = test_helpers.read_generator_corpus(corpus_name)
    honeycomb.generate_terraform(input) |> should.equal(Ok(expected))
  })
}

// ==== window_to_time_period ====
// * ✅ 1 -> 1 (minimum)
// * ✅ 30 -> 30
// * ✅ 90 -> 90 (maximum)
// Range (1-90) enforced by standard library type constraint at linker level.
pub fn window_to_time_period_test() {
  [
    #("1 -> 1 (minimum)", 1, 1),
    #("30 -> 30", 30, 30),
    #("90 -> 90 (maximum)", 90, 90),
  ]
  |> test_helpers.table_test_1(honeycomb.window_to_time_period)
}

// ==== ir_to_terraform_resources ====
// * ❌ evaluation references undefined indicator returns error
// * ❌ missing evaluation returns error
pub fn ir_to_terraform_resources_undefined_indicator_test() {
  let ir =
    make_honeycomb_ir(
      "Empty SLO",
      "acme_payments_empty",
      "acme",
      "platform",
      "payments",
      "test_blueprint",
      99.0,
      30,
      "sli",
      [],
    )

  case honeycomb.ir_to_terraform_resources(ir) {
    Error(errors.GeneratorTerraformResolutionError(msg:, ..)) ->
      string.contains(msg, "undefined indicators")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn ir_to_terraform_resources_missing_evaluation_test() {
  // Build an IR without an evaluation value to test the error path.
  let ir =
    ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: "No Eval SLO",
        org_name: "acme",
        service_name: "payments",
        blueprint_name: "test_blueprint",
        team_name: "platform",
        misc: dict.new(),
      ),
      unique_identifier: "acme_payments_no_eval",
      artifact_refs: [SLO],
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          value.StringValue(constants.vendor_honeycomb),
        ),
        helpers.ValueTuple(
          "threshold",
          types.PrimitiveType(types.NumericType(types.Float)),
          value.FloatValue(99.0),
        ),
        helpers.ValueTuple(
          "window_in_days",
          types.PrimitiveType(types.NumericType(types.Integer)),
          value.IntValue(30),
        ),
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          value.DictValue(
            dict.from_list([
              #("sli", value.StringValue("LT($\"status_code\", 500)")),
            ]),
          ),
        ),
      ],
      artifact_data: ir.slo_only(ir.SloFields(
        threshold: 99.0,
        indicators: dict.from_list([#("sli", "LT($\"status_code\", 500)")]),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: option.Some(vendor.Honeycomb),
    )

  case honeycomb.ir_to_terraform_resources(ir) {
    Error(errors.GeneratorTerraformResolutionError(msg:, ..)) ->
      string.contains(msg, "missing evaluation")
      |> should.be_true
    _ -> should.fail()
  }
}

// ==== sanitize_honeycomb_tag_key ====
// * ✅ removes underscores
// * ✅ removes digits
// * ✅ lowercases letters
// * ✅ truncates to 32 chars
pub fn sanitize_honeycomb_tag_key_test() {
  [
    #("removes underscores", "managed_by", "managedby"),
    #("removes underscores and digits", "caffeine_version", "caffeineversion"),
    #("already valid", "org", "org"),
    #("lowercases", "MyKey", "mykey"),
    #("removes digits", "key123", "key"),
    #("removes hyphens", "my-key", "mykey"),
  ]
  |> test_helpers.table_test_1(honeycomb.sanitize_honeycomb_tag_key)
}

// ==== sanitize_honeycomb_tag_value ====
// * ✅ lowercases and replaces spaces with hyphens
// * ✅ prefixes digit-leading values with "v"
// * ✅ replaces underscores with hyphens
// * ✅ strips invalid characters
pub fn sanitize_honeycomb_tag_value_test() {
  [
    #("already valid", "caffeine", "caffeine"),
    #("lowercases and replaces spaces", "API Success Rate", "api-success-rate"),
    #("prefixes digit-leading values", "4.5.0", "v450"),
    #("replaces underscores", "trace_availability", "trace-availability"),
    #("uppercased value", "Uptime", "uptime"),
    #(
      "spaces and mixed case",
      "Caffeine Lang Main Website is Up",
      "caffeine-lang-main-website-is-up",
    ),
  ]
  |> test_helpers.table_test_1(honeycomb.sanitize_honeycomb_tag_value)
}
