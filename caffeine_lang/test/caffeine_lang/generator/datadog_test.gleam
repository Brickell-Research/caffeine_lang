import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/constants
import caffeine_lang/common/errors
import caffeine_lang/common/helpers
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/semantic_types
import caffeine_lang/generator/datadog
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.5),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(7),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "value",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string("(good + partial) / total"),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "value",
              accepted_types.PrimitiveType(primitive_types.String),
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
          artifact_refs: ["SLO", "DependencyRelations"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
              dynamic.properties([
                #(
                  dynamic.string("soft"),
                  dynamic.list([
                    dynamic.string("cache_slo"),
                    dynamic.string("logging_slo"),
                  ]),
                ),
                #(
                  dynamic.string("hard"),
                  dynamic.list([
                    dynamic.string("db_slo"),
                    dynamic.string("storage_slo"),
                  ]),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO", "DependencyRelations"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
              dynamic.properties([
                #(
                  dynamic.string("hard"),
                  dynamic.list([
                    dynamic.string("db_slo"),
                    dynamic.string("storage_slo"),
                  ]),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO", "DependencyRelations"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
              dynamic.properties([
                #(
                  dynamic.string("soft"),
                  dynamic.list([
                    dynamic.string("cache_slo"),
                    dynamic.string("logging_slo"),
                  ]),
                ),
                #(
                  dynamic.string("hard"),
                  dynamic.list([dynamic.string("db_slo")]),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
            helpers.ValueTuple(
              "tags",
              accepted_types.ModifierType(modifier_types.Optional(
                accepted_types.CollectionType(collection_types.Dict(
                  accepted_types.PrimitiveType(primitive_types.String),
                  accepted_types.PrimitiveType(primitive_types.String),
                )),
              )),
              dynamic.properties([]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
            helpers.ValueTuple(
              "tags",
              accepted_types.ModifierType(modifier_types.Optional(
                accepted_types.CollectionType(collection_types.Dict(
                  accepted_types.PrimitiveType(primitive_types.String),
                  accepted_types.PrimitiveType(primitive_types.String),
                )),
              )),
              dynamic.properties([
                #(dynamic.string("env"), dynamic.string("prod")),
                #(dynamic.string("tier"), dynamic.string("1")),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
            helpers.ValueTuple(
              "tags",
              accepted_types.ModifierType(modifier_types.Optional(
                accepted_types.CollectionType(collection_types.Dict(
                  accepted_types.PrimitiveType(primitive_types.String),
                  accepted_types.PrimitiveType(primitive_types.String),
                )),
              )),
              dynamic.properties([
                #(dynamic.string("team"), dynamic.string("override_team")),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_overshadowing_tags",
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Float,
              )),
              dynamic.float(99.9),
            ),
            helpers.ValueTuple(
              "window_in_days",
              accepted_types.PrimitiveType(primitive_types.NumericType(
                numeric_types.Integer,
              )),
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
              )),
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
            helpers.ValueTuple(
              "runbook",
              accepted_types.ModifierType(modifier_types.Optional(
                accepted_types.PrimitiveType(primitive_types.SemanticType(
                  semantic_types.URL,
                )),
              )),
              dynamic.string(
                "https://wiki.example.com/runbook/auth-latency",
              ),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_runbook",
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
