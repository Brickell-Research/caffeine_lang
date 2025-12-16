import caffeine_lang/common/accepted_types.{Dict, Float, Integer, String}
import caffeine_lang/common/constants
import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/generator/datadog
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
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
  content
}

// ==== terraform_settings ====
// * ✅ includes Datadog provider requirement
// * ✅ version constraint is ~> 3.0
pub fn terraform_settings_test() {
  let settings = datadog.terraform_settings()

  // Check that datadog provider is required
  dict.get(settings.required_providers, constants.vendor_datadog)
  |> should.be_ok

  // Check version constraint
  let assert Ok(provider_req) =
    dict.get(settings.required_providers, constants.vendor_datadog)
  provider_req.source |> should.equal("DataDog/datadog")
  provider_req.version |> should.equal(option.Some("~> 3.0"))
}

// ==== provider ====
// * ✅ provider name is datadog
// * ✅ uses variable references for credentials
pub fn provider_test() {
  let provider = datadog.provider()

  provider.name |> should.equal(constants.vendor_datadog)
  provider.alias |> should.equal(option.None)

  // Check that api_key and app_key attributes exist
  dict.get(provider.attributes, "api_key") |> should.be_ok
  dict.get(provider.attributes, "app_key") |> should.be_ok
}

// ==== variables ====
// * ✅ includes datadog_api_key variable
// * ✅ includes datadog_app_key variable
// * ✅ variables are marked as sensitive
pub fn variables_test() {
  let vars = datadog.variables()

  // Should have 2 variables
  list.length(vars) |> should.equal(2)

  // Find api_key variable
  let api_key_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "datadog_api_key" })
  api_key_var |> should.be_ok
  let assert Ok(api_key) = api_key_var
  api_key.sensitive |> should.equal(option.Some(True))
  api_key.description |> should.equal(option.Some("Datadog API key"))

  // Find app_key variable
  let app_key_var =
    list.find(vars, fn(v: terraform.Variable) { v.name == "datadog_app_key" })
  app_key_var |> should.be_ok
  let assert Ok(app_key) = app_key_var
  app_key.sensitive |> should.equal(option.Some(True))
  app_key.description |> should.equal(option.Some("Datadog Application key"))
}

// ==== generate_terraform ====
// * ✅ simple SLO with numerator/denominator queries
// * ✅ SLO with resolved template queries (tags filled in)
// * ✅ multiple SLOs generate multiple resources
// * ✅ complex CQL expression (good + partial) / total
// * ✅ fully resolved SLO time slice
pub fn generate_terraform_test() {
  [
    // simple SLO with numerator/denominator queries
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "Auth Latency SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              Dict(String, String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{*}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "simple_slo",
    ),
    // SLO with resolved template queries (tags filled in)
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "Auth Latency SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              Dict(String, String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{env:production,status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{env:production}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "resolved_templates",
    ),
    // multiple SLOs generate multiple resources
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "Auth Latency SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              Dict(String, String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{*}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "API Availability SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/api/availability_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.5)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(7),
            ),
            helpers.ValueTuple(
              "queries",
              Dict(String, String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:api.requests{!status:5xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:api.requests{*}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "multiple_slos",
    ),
    // complex CQL expression: (good + partial) / total
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "Composite SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/composite_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "value",
              String,
              dynamic.string("(good + partial) / total"),
            ),
            helpers.ValueTuple(
              "queries",
              Dict(String, String),
              dynamic.properties([
                #(
                  dynamic.string("good"),
                  dynamic.string("sum:http.requests{status:2xx}"),
                ),
                #(
                  dynamic.string("partial"),
                  dynamic.string("sum:http.requests{status:3xx}"),
                ),
                #(
                  dynamic.string("total"),
                  dynamic.string("sum:http.requests{*}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "complex_expression",
    ),
    // fully resolved SLO time slice
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "Time Slice SLO",
            org_name: "org",
            service_name: "team",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/time_slice_slo",
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              String,
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple("threshold", Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "value",
              String,
              dynamic.string(
                "time_slice(avg:system.cpu.user{env:production} > 99.5 per 300s)",
              ),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "resolved_time_slice_expression",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_file) = pair
    let expected = read_corpus(corpus_file)
    datadog.generate_terraform(input) |> should.equal(Ok(expected))
  })
}

// ==== window_to_timeframe ====
// * ✅ 7 -> "7d"
// * ✅ 30 -> "30d"
// * ✅ 90 -> "90d"
// * ✅ 120 -> "120d"
pub fn window_to_timeframe_test() {
  [
    #(7, Ok("7d")),
    #(30, Ok("30d")),
    #(90, Ok("90d")),
    #(
      120,
      Error(errors.GeneratorDatadogTerraformResolutionError(
        msg: "Illegal window_in_days value: 120. Accepted values are 7, 30, or 90.",
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(datadog.window_to_timeframe)
}

// ==== extract_string ====
// * ✅ extracts String ValueTuple
// * ✅ returns Error for missing label
pub fn extract_string_test() {
  [
    // extracts String ValueTuple
    #(
      [
        helpers.ValueTuple(
          "vendor",
          String,
          dynamic.string(constants.vendor_datadog),
        ),
      ],
      "vendor",
      Ok(constants.vendor_datadog),
    ),
    // returns Error for missing label
    #(
      [
        helpers.ValueTuple(
          "vendor",
          String,
          dynamic.string(constants.vendor_datadog),
        ),
      ],
      "missing",
      Error(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(datadog.extract_string)
}

// ==== extract_float ====
// * ✅ extracts Float ValueTuple
// * ✅ returns Error for missing label
pub fn extract_float_test() {
  [
    // extracts Float ValueTuple
    #(
      [helpers.ValueTuple("threshold", Float, dynamic.float(99.9))],
      "threshold",
      Ok(99.9),
    ),
    // returns Error for missing label
    #(
      [helpers.ValueTuple("threshold", Float, dynamic.float(99.9))],
      "missing",
      Error(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(datadog.extract_float)
}

// ==== extract_int ====
// * ✅ extracts Integer ValueTuple
// * ✅ returns Error for missing label
pub fn extract_int_test() {
  [
    // extracts Integer ValueTuple
    #(
      [helpers.ValueTuple("window_in_days", Integer, dynamic.int(30))],
      "window_in_days",
      Ok(30),
    ),
    // returns Error for missing label
    #(
      [helpers.ValueTuple("window_in_days", Integer, dynamic.int(30))],
      "missing",
      Error(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(datadog.extract_int)
}

// ==== extract_dict_string_string ====
// * ✅ extracts Dict(String, String) ValueTuple
// * ✅ returns Error for missing label
pub fn extract_dict_string_string_test() {
  [
    // extracts Dict(String, String) ValueTuple
    #(
      [
        helpers.ValueTuple(
          "queries",
          Dict(String, String),
          dynamic.properties([
            #(dynamic.string("numerator"), dynamic.string("sum:good")),
            #(dynamic.string("denominator"), dynamic.string("sum:total")),
          ]),
        ),
      ],
      "queries",
      Ok(
        dict.from_list([
          #("numerator", "sum:good"),
          #("denominator", "sum:total"),
        ]),
      ),
    ),
    // returns Error for missing label
    #(
      [
        helpers.ValueTuple(
          "queries",
          Dict(String, String),
          dynamic.properties([]),
        ),
      ],
      "missing",
      Error(Nil),
    ),
  ]
  |> test_helpers.array_based_test_executor_2(
    datadog.extract_dict_string_string,
  )
}
