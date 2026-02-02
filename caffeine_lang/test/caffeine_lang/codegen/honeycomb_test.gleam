import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/honeycomb
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import simplifile
import terra_madre/terraform
import test_helpers

// ==== Helpers ====
fn corpus_path(file_name: String) {
  "test/caffeine_lang/corpus/generator/" <> file_name <> ".tf"
}

fn read_corpus(file_name: String) -> String {
  let assert Ok(content) = simplifile.read(corpus_path(file_name))
  // Replace version placeholder with actual version constant
  string.replace(content, "{{VERSION}}", constants.version)
}

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
) -> semantic_analyzer.IntermediateRepresentation {
  semantic_analyzer.IntermediateRepresentation(
    metadata: semantic_analyzer.IntermediateRepresentationMetaData(
      friendly_label: friendly_label,
      org_name: org,
      service_name: service,
      blueprint_name: blueprint,
      team_name: team,
      misc: dict.new(),
    ),
    unique_identifier: unique_identifier,
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
        value.FloatValue(threshold),
      ),
      helpers.ValueTuple(
        "window_in_days",
        types.PrimitiveType(types.NumericType(types.Integer)),
        value.IntValue(window_in_days),
      ),
      helpers.ValueTuple(
        "evaluation",
        types.PrimitiveType(types.String),
        value.StringValue(evaluation),
      ),
      helpers.ValueTuple(
        "indicators",
        types.CollectionType(types.Dict(
          types.PrimitiveType(types.String),
          types.PrimitiveType(types.String),
        )),
        value.DictValue(
          indicators
          |> list.map(fn(pair) { #(pair.0, value.StringValue(pair.1)) })
          |> dict.from_list,
        ),
      ),
    ],
    artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
      threshold: threshold,
      indicators: indicators |> dict.from_list,
      window_in_days: window_in_days,
      evaluation: option.Some(evaluation),
      tags: [],
      runbook: option.None,
    )),
    vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
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
    let expected = read_corpus(corpus_name)
    honeycomb.generate_terraform(input) |> should.equal(Ok(expected))
  })
}

// ==== window_to_time_period ====
// * ✅ 1 -> Ok(1) (minimum)
// * ✅ 30 -> Ok(30)
// * ✅ 90 -> Ok(90) (maximum)
// * ❌ 0 -> Error
// * ❌ 91 -> Error
pub fn window_to_time_period_test() {
  [
    #(1, Ok(1)),
    #(30, Ok(30)),
    #(90, Ok(90)),
    #(
      0,
      Error(errors.GeneratorHoneycombTerraformResolutionError(
        msg: "Illegal window_in_days value: 0. Honeycomb accepts values between 1 and 90.",
      )),
    ),
    #(
      91,
      Error(errors.GeneratorHoneycombTerraformResolutionError(
        msg: "Illegal window_in_days value: 91. Honeycomb accepts values between 1 and 90.",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(honeycomb.window_to_time_period)
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
    Error(errors.GeneratorHoneycombTerraformResolutionError(msg:)) ->
      string.contains(msg, "undefined indicators")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn ir_to_terraform_resources_missing_evaluation_test() {
  // Build an IR without an evaluation value to test the error path.
  let ir =
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
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
      artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
        threshold: 99.0,
        indicators: dict.from_list([#("sli", "LT($\"status_code\", 500)")]),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
    )

  case honeycomb.ir_to_terraform_resources(ir) {
    Error(errors.GeneratorHoneycombTerraformResolutionError(msg:)) ->
      string.contains(msg, "missing evaluation")
      |> should.be_true
    _ -> should.fail()
  }
}
