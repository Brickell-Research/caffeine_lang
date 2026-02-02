import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{DependencyRelations, Hard, SLO, Soft}
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue(
                      "sum:http.requests{env:production,status:2xx}",
                    ),
                  ),
                  #(
                    "denominator",
                    value.StringValue("sum:http.requests{env:production}"),
                  ),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{env:production,status:2xx}"),
              #("denominator", "sum:http.requests{env:production}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.5),
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
                  #(
                    "numerator",
                    value.StringValue("sum:api.requests{!status:5xx}"),
                  ),
                  #("denominator", value.StringValue("sum:api.requests{*}")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.5,
            indicators: dict.from_list([
              #("numerator", "sum:api.requests{!status:5xx}"),
              #("denominator", "sum:api.requests{*}"),
            ]),
            window_in_days: 7,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              types.PrimitiveType(types.NumericType(types.Integer)),
              value.IntValue(30),
            ),
            helpers.ValueTuple(
              "evaluation",
              types.PrimitiveType(types.String),
              value.StringValue("(good + partial) / total"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              value.DictValue(
                dict.from_list([
                  #("good", value.StringValue("sum:http.requests{status:2xx}")),
                  #(
                    "partial",
                    value.StringValue("sum:http.requests{status:3xx}"),
                  ),
                  #("total", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("good", "sum:http.requests{status:2xx}"),
              #("partial", "sum:http.requests{status:3xx}"),
              #("total", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.Some("(good + partial) / total"),
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              types.PrimitiveType(types.NumericType(types.Integer)),
              value.IntValue(30),
            ),
            helpers.ValueTuple(
              "evaluation",
              types.PrimitiveType(types.String),
              value.StringValue(
                "time_slice(avg:system.cpu.user{env:production} > 99.5 per 300s)",
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.Some(
              "time_slice(avg:system.cpu.user{env:production} > 99.5 per 300s)",
            ),
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "resolved_time_slice_expression",
    ),
    // SLO with both hard and soft dependencies (multiple each)
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
          artifact_refs: [SLO, DependencyRelations],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "relations",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.CollectionType(
                  types.List(types.PrimitiveType(types.String)),
                ),
              )),
              value.DictValue(
                dict.from_list([
                  #(
                    "soft",
                    value.ListValue([
                      value.StringValue("cache_slo"),
                      value.StringValue("logging_slo"),
                    ]),
                  ),
                  #(
                    "hard",
                    value.ListValue([
                      value.StringValue("db_slo"),
                      value.StringValue("storage_slo"),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloWithDependency(
            slo: semantic_analyzer.SloFields(
              vendor_string: constants.vendor_datadog,
              threshold: 99.9,
              indicators: dict.from_list([
                #("numerator", "sum:http.requests{status:2xx}"),
                #("denominator", "sum:http.requests{*}"),
              ]),
              window_in_days: 30,
              evaluation: option.None,
              tags: [],
              runbook: option.None,
            ),
            dependency: semantic_analyzer.DependencyFields(
              relations: dict.from_list([
                #(Soft, ["cache_slo", "logging_slo"]),
                #(Hard, ["db_slo", "storage_slo"]),
              ]),
              tags: [],
            ),
          ),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_both_dependencies",
    ),
    // SLO with only hard dependencies
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
          artifact_refs: [SLO, DependencyRelations],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "relations",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.CollectionType(
                  types.List(types.PrimitiveType(types.String)),
                ),
              )),
              value.DictValue(
                dict.from_list([
                  #(
                    "hard",
                    value.ListValue([
                      value.StringValue("db_slo"),
                      value.StringValue("storage_slo"),
                    ]),
                  ),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloWithDependency(
            slo: semantic_analyzer.SloFields(
              vendor_string: constants.vendor_datadog,
              threshold: 99.9,
              indicators: dict.from_list([
                #("numerator", "sum:http.requests{status:2xx}"),
                #("denominator", "sum:http.requests{*}"),
              ]),
              window_in_days: 30,
              evaluation: option.None,
              tags: [],
              runbook: option.None,
            ),
            dependency: semantic_analyzer.DependencyFields(
              relations: dict.from_list([
                #(Hard, ["db_slo", "storage_slo"]),
              ]),
              tags: [],
            ),
          ),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_hard_dependency_only",
    ),
    // SLO with mixed dependencies (soft has multiple, hard has one)
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
          artifact_refs: [SLO, DependencyRelations],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "relations",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.CollectionType(
                  types.List(types.PrimitiveType(types.String)),
                ),
              )),
              value.DictValue(
                dict.from_list([
                  #(
                    "soft",
                    value.ListValue([
                      value.StringValue("cache_slo"),
                      value.StringValue("logging_slo"),
                    ]),
                  ),
                  #("hard", value.ListValue([value.StringValue("db_slo")])),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloWithDependency(
            slo: semantic_analyzer.SloFields(
              vendor_string: constants.vendor_datadog,
              threshold: 99.9,
              indicators: dict.from_list([
                #("numerator", "sum:http.requests{status:2xx}"),
                #("denominator", "sum:http.requests{*}"),
              ]),
              window_in_days: 30,
              evaluation: option.None,
              tags: [],
              runbook: option.None,
            ),
            dependency: semantic_analyzer.DependencyFields(
              relations: dict.from_list([
                #(Soft, ["cache_slo", "logging_slo"]),
                #(Hard, ["db_slo"]),
              ]),
              tags: [],
            ),
          ),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_mixed_dependencies",
    ),
    // SLO with empty tags dict
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "tags",
              types.ModifierType(
                types.Optional(
                  types.CollectionType(types.Dict(
                    types.PrimitiveType(types.String),
                    types.PrimitiveType(types.String),
                  )),
                ),
              ),
              value.DictValue(dict.from_list([])),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_empty_tags",
    ),
    // SLO with user-provided tags
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "tags",
              types.ModifierType(
                types.Optional(
                  types.CollectionType(types.Dict(
                    types.PrimitiveType(types.String),
                    types.PrimitiveType(types.String),
                  )),
                ),
              ),
              value.DictValue(
                dict.from_list([
                  #("env", value.StringValue("prod")),
                  #("tier", value.StringValue("1")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [#("env", "prod"), #("tier", "1")],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_tags",
    ),
    // SLO with overshadowing user tag
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "tags",
              types.ModifierType(
                types.Optional(
                  types.CollectionType(types.Dict(
                    types.PrimitiveType(types.String),
                    types.PrimitiveType(types.String),
                  )),
                ),
              ),
              value.DictValue(
                dict.from_list([
                  #("team", value.StringValue("override_team")),
                ]),
              ),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [#("team", "override_team")],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_overshadowing_tags_WITH_WARNINGS",
    ),
    // SLO with runbook URL
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
          artifact_refs: [SLO],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.FloatValue(99.9),
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
                    "numerator",
                    value.StringValue("sum:http.requests{status:2xx}"),
                  ),
                  #("denominator", value.StringValue("sum:http.requests{*}")),
                ]),
              ),
            ),
            helpers.ValueTuple(
              "runbook",
              types.ModifierType(
                types.Optional(
                  types.PrimitiveType(types.SemanticType(types.URL)),
                ),
              ),
              value.StringValue("https://wiki.example.com/runbook/auth-latency"),
            ),
          ],
          artifact_data: semantic_analyzer.SloOnly(semantic_analyzer.SloFields(
            vendor_string: constants.vendor_datadog,
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.Some(
              "https://wiki.example.com/runbook/auth-latency",
            ),
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ],
      "slo_with_runbook",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_file) = pair
    case string.ends_with(corpus_file, "_WITH_WARNINGS") {
      True -> {
        let actual_corpus =
          string.drop_end(corpus_file, string.length("_WITH_WARNINGS"))
        let expected = read_corpus(actual_corpus)
        let result = datadog.generate_terraform(input)
        case result {
          Ok(#(tf, warnings)) -> {
            tf |> should.equal(expected)
            { !list.is_empty(warnings) } |> should.be_true()
          }
          Error(_) -> should.fail()
        }
      }
      False -> {
        let expected = read_corpus(corpus_file)
        datadog.generate_terraform(input) |> should.equal(Ok(#(expected, [])))
      }
    }
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
