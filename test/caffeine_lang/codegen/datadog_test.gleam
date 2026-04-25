import caffeine_lang/analysis/vendor
import caffeine_lang/codegen/datadog
import caffeine_lang/codegen/platforms
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/identifiers
import caffeine_lang/linker/artifacts.{Hard, Soft}
import caffeine_lang/linker/ir.{
  type IntermediateRepresentation, IntermediateRepresentation, SloFields,
}
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should
import terra_madre/terraform
import test_helpers

// ==== Helpers ====

// ==== terraform_settings ====
// * ✅ includes Datadog provider requirement
// * ✅ version constraint is ~> 3.0
pub fn terraform_settings_test() {
  let settings = platforms.terraform_settings(platforms.for_vendor(vendor.Datadog))

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
  let provider = platforms.provider(platforms.for_vendor(vendor.Datadog))

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
  let vars = platforms.for_vendor(vendor.Datadog).variables

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
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "simple_slo",
    ),
    // SLO with resolved template queries (tags filled in)
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{env:production,status:2xx}"),
              #("denominator", "sum:http.requests{env:production}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "resolved_templates",
    ),
    // multiple SLOs generate multiple resources
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("API Availability SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/api/availability_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.5),
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
          slo: ir.SloFields(
            threshold: 99.5,
            indicators: dict.from_list([
              #("numerator", "sum:api.requests{!status:5xx}"),
              #("denominator", "sum:api.requests{*}"),
            ]),
            window_in_days: 7,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "multiple_slos",
    ),
    // complex CQL expression: (good + partial) / total
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Composite SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/composite_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
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
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "complex_expression",
    ),
    // fully resolved SLO time slice
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Time Slice SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/time_slice_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.Some(
              "time_slice(avg:system.cpu.user{env:production} > 99.5 per 300s)",
            ),
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "resolved_time_slice_expression",
    ),
    // SLO with both hard and soft dependencies (multiple each)
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.Some(
              dict.from_list([
                #(Soft, ["cache_slo", "logging_slo"]),
                #(Hard, ["db_slo", "storage_slo"]),
              ]),
            ),
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_both_dependencies",
    ),
    // SLO with only hard dependencies
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.Some(
              dict.from_list([
                #(Hard, ["db_slo", "storage_slo"]),
              ]),
            ),
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_hard_dependency_only",
    ),
    // SLO with mixed dependencies (soft has multiple, hard has one)
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.Some(
              dict.from_list([
                #(Soft, ["cache_slo", "logging_slo"]),
                #(Hard, ["db_slo"]),
              ]),
            ),
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_mixed_dependencies",
    ),
    // SLO with empty tags dict
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_empty_tags",
    ),
    // SLO with user-provided tags
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [#("env", "prod"), #("tier", "1")],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_tags",
    ),
    // SLO with overshadowing user tag
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
            threshold: 99.9,
            indicators: dict.from_list([
              #("numerator", "sum:http.requests{status:2xx}"),
              #("denominator", "sum:http.requests{*}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [#("team", "override_team")],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      "slo_with_overshadowing_tags_WITH_WARNINGS",
    ),
    // SLO with runbook URL
    #(
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("Auth Latency SLO"),
            org_name: identifiers.OrgName("org"),
            service_name: identifiers.ServiceName("team"),
            measurement_name: identifiers.MeasurementName("test_measurement"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "org/team/auth/latency_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "threshold",
              types.PrimitiveType(types.NumericType(types.Float)),
              value.PercentageValue(99.9),
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
          slo: ir.SloFields(
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
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
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
        let expected = test_helpers.read_generator_corpus(actual_corpus)
        let result =
          platforms.generate_terraform(platforms.for_vendor(vendor.Datadog), input)
          |> test_helpers.normalize_terraform_result_with_warnings
        case result {
          Ok(#(tf, warnings)) -> {
            tf |> should.equal(expected)
            { !list.is_empty(warnings) } |> should.be_true()
          }
          Error(_) -> should.fail()
        }
      }
      False -> {
        let expected = test_helpers.read_generator_corpus(corpus_file)
        platforms.generate_terraform(platforms.for_vendor(vendor.Datadog), input)
        |> test_helpers.normalize_terraform_result_with_warnings
        |> should.equal(Ok(#(expected, [])))
      }
    }
  })
}

// ==== resolve_indicators ====
// * ❌ missing 'indicators' field in IR values
// * ❌ failed to decode indicators (non-string dict)
// * ❌ failed to decode 'evaluation' field as string
pub fn resolve_indicators_missing_indicators_test() {
  // IR with no "indicators" ValueTuple at all
  let ir: IntermediateRepresentation(ir.DepsValidated) =
    IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("Test SLO"),
        org_name: identifiers.OrgName("org"),
        service_name: identifiers.ServiceName("svc"),
        measurement_name: identifiers.MeasurementName("bp"),
        team_name: identifiers.TeamName("team"),
        misc: dict.new(),
      ),
      unique_identifier: "org_svc_test",
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          value.StringValue(constants.vendor_datadog),
        ),
      ],
      slo: SloFields(
        threshold: 99.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.Some(vendor.Datadog),
    )

  case datadog.resolve_indicators(ir) {
    Error(errors.SemanticAnalysisTemplateResolutionError(msg:, ..)) ->
      string.contains(msg, "missing 'indicators' field")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn resolve_indicators_bad_decode_test() {
  // IR with "indicators" but value is IntValue (not a dict)
  let ir: IntermediateRepresentation(ir.DepsValidated) =
    IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("Test SLO"),
        org_name: identifiers.OrgName("org"),
        service_name: identifiers.ServiceName("svc"),
        measurement_name: identifiers.MeasurementName("bp"),
        team_name: identifiers.TeamName("team"),
        misc: dict.new(),
      ),
      unique_identifier: "org_svc_test",
      values: [
        helpers.ValueTuple(
          "indicators",
          types.PrimitiveType(types.NumericType(types.Integer)),
          value.IntValue(42),
        ),
      ],
      slo: SloFields(
        threshold: 99.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.Some(vendor.Datadog),
    )

  case datadog.resolve_indicators(ir) {
    Error(errors.SemanticAnalysisTemplateResolutionError(msg:, ..)) ->
      string.contains(msg, "failed to decode indicators")
      |> should.be_true
    _ -> should.fail()
  }
}

pub fn resolve_indicators_bad_evaluation_decode_test() {
  // IR with "evaluation" as IntValue (not a string)
  let ir: IntermediateRepresentation(ir.DepsValidated) =
    IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("Test SLO"),
        org_name: identifiers.OrgName("org"),
        service_name: identifiers.ServiceName("svc"),
        measurement_name: identifiers.MeasurementName("bp"),
        team_name: identifiers.TeamName("team"),
        misc: dict.new(),
      ),
      unique_identifier: "org_svc_test",
      values: [
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          value.DictValue(
            dict.from_list([
              #("numerator", value.StringValue("count:test")),
            ]),
          ),
        ),
        helpers.ValueTuple(
          "evaluation",
          types.PrimitiveType(types.NumericType(types.Integer)),
          value.IntValue(99),
        ),
      ],
      slo: SloFields(
        threshold: 99.0,
        indicators: dict.from_list([#("numerator", "count:test")]),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.Some(vendor.Datadog),
    )

  case datadog.resolve_indicators(ir) {
    Error(errors.SemanticAnalysisTemplateResolutionError(msg:, ..)) ->
      string.contains(msg, "failed to decode 'evaluation' field as string")
      |> should.be_true
    _ -> should.fail()
  }
}

// ==== window_to_timeframe ====
// * ✅ 7 -> "7d"
// * ✅ 30 -> "30d"
// * ✅ 90 -> "90d"
// * ❌ 15 -> Error (in range 1-90 but not in Datadog's {7,30,90})
pub fn window_to_timeframe_test() {
  [
    #("7 -> 7d", 7, Ok("7d")),
    #("30 -> 30d", 30, Ok("30d")),
    #("90 -> 90d", 90, Ok("90d")),
    #(
      "15 -> Error (not in Datadog's accepted set)",
      15,
      Error(errors.GeneratorTerraformResolutionError(
        vendor: constants.vendor_datadog,
        msg: "Illegal window_in_days value: 15. Accepted values are 7, 30, or 90.",
        context: errors.empty_context(),
      )),
    ),
  ]
  |> test_helpers.table_test_1(datadog.window_to_timeframe)
}
