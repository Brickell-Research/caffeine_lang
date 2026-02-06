import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/newrelic
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
  string.replace(content, "{{VERSION}}", constants.version)
}

fn make_newrelic_ir(
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
        value.StringValue(constants.vendor_newrelic),
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
    vendor: semantic_analyzer.ResolvedVendor(vendor.NewRelic),
  )
}

// ==== terraform_settings ====
// * ✅ includes newrelic provider requirement
// * ✅ version constraint is ~> 3.0
pub fn terraform_settings_test() {
  let settings = newrelic.terraform_settings()

  dict.get(settings.required_providers, "newrelic")
  |> should.be_ok

  let assert Ok(provider_req) =
    dict.get(settings.required_providers, "newrelic")
  provider_req.source |> should.equal("newrelic/newrelic")
  provider_req.version |> should.equal(option.Some("~> 3.0"))
}

// ==== provider ====
// * ✅ provider name is newrelic
// * ✅ uses variable references for account_id, api_key, and region
pub fn provider_test() {
  let provider = newrelic.provider()

  provider.name |> should.equal("newrelic")
  provider.alias |> should.equal(option.None)

  dict.get(provider.attributes, "account_id") |> should.be_ok
  dict.get(provider.attributes, "api_key") |> should.be_ok
  dict.get(provider.attributes, "region") |> should.be_ok
}

// ==== variables ====
// * ✅ includes newrelic_account_id variable (number, not sensitive)
// * ✅ includes newrelic_api_key variable (string, sensitive)
// * ✅ includes newrelic_region variable (string, default "US")
// * ✅ includes newrelic_entity_guid variable (string, not sensitive)
pub fn variables_test() {
  let vars = newrelic.variables()

  list.length(vars) |> should.equal(4)

  let account_id_var =
    list.find(vars, fn(v: terraform.Variable) {
      v.name == "newrelic_account_id"
    })
  account_id_var |> should.be_ok
  let assert Ok(account_id) = account_id_var
  account_id.sensitive |> should.equal(option.None)
  account_id.description |> should.equal(option.Some("New Relic account ID"))

  let api_key_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "newrelic_api_key" })
  api_key_var |> should.be_ok
  let assert Ok(api_key) = api_key_var
  api_key.sensitive |> should.equal(option.Some(True))
  api_key.description |> should.equal(option.Some("New Relic API key"))

  let region_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "newrelic_region" })
  region_var |> should.be_ok
  let assert Ok(region) = region_var
  region.sensitive |> should.equal(option.None)
  region.description |> should.equal(option.Some("New Relic region"))

  let entity_guid_var =
    list.find(vars, fn(v: terraform.Variable) {
      v.name == "newrelic_entity_guid"
    })
  entity_guid_var |> should.be_ok
  let assert Ok(entity_guid) = entity_guid_var
  entity_guid.sensitive |> should.equal(option.None)
  entity_guid.description
  |> should.equal(option.Some("New Relic entity GUID"))
}

// ==== window_to_rolling_count ====
// * ✅ 1 -> Ok(1)
// * ✅ 7 -> Ok(7)
// * ✅ 28 -> Ok(28)
// * ❌ 30 -> Error
// * ❌ 0 -> Error
pub fn window_to_rolling_count_test() {
  [
    #(1, Ok(1)),
    #(7, Ok(7)),
    #(28, Ok(28)),
    #(
      30,
      Error(errors.GeneratorNewrelicTerraformResolutionError(
        msg: "Illegal window_in_days value: 30. New Relic accepts only 1, 7, or 28.",
      )),
    ),
    #(
      0,
      Error(errors.GeneratorNewrelicTerraformResolutionError(
        msg: "Illegal window_in_days value: 0. New Relic accepts only 1, 7, or 28.",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(newrelic.window_to_rolling_count)
}

// ==== parse_nrql_indicator ====
// * ✅ simple event type
// * ✅ event type with WHERE clause
// * ✅ event type with multiple WHERE clauses
pub fn parse_nrql_indicator_test() {
  newrelic.parse_nrql_indicator("Transaction")
  |> should.equal(#("Transaction", option.None))

  newrelic.parse_nrql_indicator("Transaction WHERE appName = 'payments'")
  |> should.equal(#("Transaction", option.Some("appName = 'payments'")))

  newrelic.parse_nrql_indicator(
    "Transaction WHERE appName = 'payments' AND duration < 0.1",
  )
  |> should.equal(#(
    "Transaction",
    option.Some("appName = 'payments' AND duration < 0.1"),
  ))
}

// ==== generate_terraform ====
// * ✅ simple SLO with two indicators
pub fn generate_terraform_test() {
  [
    #(
      [
        make_newrelic_ir(
          "API Success Rate",
          "acme_payments_api_success_rate",
          "acme",
          "platform",
          "payments",
          "newrelic_availability",
          99.5,
          7,
          "good / valid",
          [
            #(
              "good",
              "Transaction WHERE appName = 'payments' AND duration < 0.1",
            ),
            #("valid", "Transaction WHERE appName = 'payments'"),
          ],
        ),
      ],
      "newrelic_simple_slo",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_name) = pair
    let expected = read_corpus(corpus_name)
    newrelic.generate_terraform(input) |> should.equal(Ok(expected))
  })
}

// ==== ir_to_terraform_resource ====
// * ❌ evaluation references undefined indicator returns error
// * ❌ missing evaluation returns error
pub fn ir_to_terraform_resource_undefined_indicator_test() {
  let ir =
    make_newrelic_ir(
      "Empty SLO",
      "acme_payments_empty",
      "acme",
      "platform",
      "payments",
      "test_blueprint",
      99.0,
      7,
      "sli",
      [],
    )

  case newrelic.ir_to_terraform_resource(ir) {
    Error(errors.GeneratorNewrelicTerraformResolutionError(msg:)) ->
      string.contains(msg, "undefined indicators")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn ir_to_terraform_resource_missing_evaluation_test() {
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
          value.StringValue(constants.vendor_newrelic),
        ),
        helpers.ValueTuple(
          "threshold",
          types.PrimitiveType(types.NumericType(types.Float)),
          value.FloatValue(99.0),
        ),
        helpers.ValueTuple(
          "window_in_days",
          types.PrimitiveType(types.NumericType(types.Integer)),
          value.IntValue(7),
        ),
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          value.DictValue(
            dict.from_list([
              #("valid", value.StringValue("Transaction")),
            ]),
          ),
        ),
      ],
      artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
        threshold: 99.0,
        indicators: dict.from_list([#("valid", "Transaction")]),
        window_in_days: 7,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: semantic_analyzer.ResolvedVendor(vendor.NewRelic),
    )

  case newrelic.ir_to_terraform_resource(ir) {
    Error(errors.GeneratorNewrelicTerraformResolutionError(msg:)) ->
      string.contains(msg, "missing evaluation")
      |> should.be_true
    _ -> should.fail()
  }
}
