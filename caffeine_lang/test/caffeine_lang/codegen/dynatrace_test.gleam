import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/dynatrace
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

fn make_dynatrace_ir(
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
    friendly_label: friendly_label,
    unique_identifier: unique_identifier,
    org: org,
    team: team,
    service: service,
    blueprint: blueprint,
    threshold: threshold,
    window_in_days: window_in_days,
    evaluation: evaluation,
    indicators: indicators,
    vendor_string: constants.vendor_dynatrace,
    vendor_enum: vendor.Dynatrace,
  )
}

// ==== terraform_settings ====
// * ✅ includes dynatrace provider requirement
// * ✅ version constraint is ~> 1.0
pub fn terraform_settings_test() {
  let settings = dynatrace.terraform_settings()

  dict.get(settings.required_providers, "dynatrace")
  |> should.be_ok

  let assert Ok(provider_req) =
    dict.get(settings.required_providers, "dynatrace")
  provider_req.source |> should.equal("dynatrace-oss/dynatrace")
  provider_req.version |> should.equal(option.Some("~> 1.0"))
}

// ==== provider ====
// * ✅ provider name is dynatrace
// * ✅ uses variable references for dt_env_url and dt_api_token
pub fn provider_test() {
  let provider = dynatrace.provider()

  provider.name |> should.equal("dynatrace")
  provider.alias |> should.equal(option.None)

  dict.get(provider.attributes, "dt_env_url") |> should.be_ok
  dict.get(provider.attributes, "dt_api_token") |> should.be_ok
}

// ==== variables ====
// * ✅ includes dynatrace_env_url variable (not sensitive)
// * ✅ includes dynatrace_api_token variable (sensitive)
pub fn variables_test() {
  let vars = dynatrace.variables()

  list.length(vars) |> should.equal(2)

  let env_url_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "dynatrace_env_url" })
  env_url_var |> should.be_ok
  let assert Ok(env_url) = env_url_var
  env_url.sensitive |> should.equal(option.None)
  env_url.description |> should.equal(option.Some("Dynatrace environment URL"))

  let api_token_var =
    list.find(vars, fn(v: terraform.Variable) {
      v.name == "dynatrace_api_token"
    })
  api_token_var |> should.be_ok
  let assert Ok(api_token) = api_token_var
  api_token.sensitive |> should.equal(option.Some(True))
  api_token.description
  |> should.equal(option.Some("Dynatrace API token"))
}

// ==== generate_terraform ====
// * ✅ simple SLO with single indicator
pub fn generate_terraform_test() {
  [
    #(
      [
        make_dynatrace_ir(
          "API Success Rate",
          "acme_payments_api_success_rate",
          "acme",
          "platform",
          "payments",
          "dynatrace_availability",
          99.5,
          30,
          "success / total",
          [
            #("success", "builtin:service.errors.server.successCount:splitBy()"),
            #("total", "builtin:service.requestCount.server:splitBy()"),
          ],
        ),
      ],
      "dynatrace_simple_slo",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_name) = pair
    let expected = test_helpers.read_generator_corpus(corpus_name)
    dynatrace.generate_terraform(input) |> should.equal(Ok(expected))
  })
}

// ==== window_to_evaluation_window ====
// * ✅ 1 -> "-1d" (minimum)
// * ✅ 30 -> "-30d"
// * ✅ 90 -> "-90d" (maximum)
// Range (1-90) enforced by standard library type constraint at linker level.
pub fn window_to_evaluation_window_test() {
  [#(1, "-1d"), #(30, "-30d"), #(90, "-90d")]
  |> test_helpers.array_based_test_executor_1(
    dynatrace.window_to_evaluation_window,
  )
}

// ==== ir_to_terraform_resource ====
// * ❌ evaluation references undefined indicator returns error
// * ❌ missing evaluation returns error
pub fn ir_to_terraform_resource_undefined_indicator_test() {
  let ir =
    make_dynatrace_ir(
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

  case dynatrace.ir_to_terraform_resource(ir) {
    Error(errors.GeneratorTerraformResolutionError(msg:, ..)) ->
      string.contains(msg, "undefined indicators")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn ir_to_terraform_resource_missing_evaluation_test() {
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
          value.StringValue(constants.vendor_dynatrace),
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
              #(
                "sli",
                value.StringValue(
                  "builtin:service.requestCount.server:splitBy()",
                ),
              ),
            ]),
          ),
        ),
      ],
      artifact_data: ir.slo_only(ir.SloFields(
        threshold: 99.0,
        indicators: dict.from_list([
          #("sli", "builtin:service.requestCount.server:splitBy()"),
        ]),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: option.Some(vendor.Dynatrace),
    )

  case dynatrace.ir_to_terraform_resource(ir) {
    Error(errors.GeneratorTerraformResolutionError(msg:, ..)) ->
      string.contains(msg, "missing evaluation")
      |> should.be_true
    _ -> should.fail()
  }
}
