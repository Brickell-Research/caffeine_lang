/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
/// Uses array-based test pattern for consistency.
import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import caffeine_lang/errors
import caffeine_lang/helpers
import caffeine_lang/identifiers

import caffeine_lang/linker/ir
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/option
import gleam/set
import gleeunit/should
import test_helpers

// ==== resolve_intermediate_representations ====
// * ✅ happy path - two IRs with vendor resolution and indicator template resolution
pub fn resolve_intermediate_representations_test() {
  [
    // happy path - two IRs with indicator template resolution
    #(
      "two IRs with vendor resolution and indicator template resolution",
      [
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("SLO One"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "slo_one",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              value.StringValue("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              value.DictValue(
                dict.from_list([
                  #("query_a", value.StringValue("avg:memory{$$env->env$$}")),
                ]),
              ),
            ),
          ],
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
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
            friendly_label: identifiers.ExpectationLabel("SLO Two"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "slo_two",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              types.PrimitiveType(types.String),
              value.StringValue("us-east"),
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
                    "query_b",
                    value.StringValue("sum:requests{$$region->region$$}"),
                  ),
                ]),
              ),
            ),
          ],
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ],
      Ok([
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("SLO One"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "slo_one",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              value.StringValue("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              value.DictValue(
                dict.from_list([
                  #("query_a", value.StringValue("avg:memory{env:staging}")),
                ]),
              ),
            ),
          ],
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_a", "avg:memory{env:staging}"),
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
            friendly_label: identifiers.ExpectationLabel("SLO Two"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "slo_two",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              types.PrimitiveType(types.String),
              value.StringValue("us-east"),
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
                    "query_b",
                    value.StringValue("sum:requests{region:us-east}"),
                  ),
                ]),
              ),
            ),
          ],
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_b", "sum:requests{region:us-east}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Datadog),
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(
    semantic_analyzer.resolve_intermediate_representations,
  )
}

// TODO: resolve_vendor has been moved to IR builder level; update or remove these tests
// // ==== resolve_vendor ====
// // * ✅ happy path - known vendor, Datadog
// pub fn resolve_vendor_test() {
//   ...
// }

// ==== resolve_indicators ====
// * ✅ happy path - multiple indicators with template variable resolution
// * ✅ happy path - defaulted param with nil uses default value
// * ✅ happy path - refinement type with defaulted inner using nil gets default value
// * ✅ happy path - lcp_p75_latency style with mix of defaulted, refinement, and provided values
pub fn resolve_indicators_test() {
  [
    // happy path - multiple queries with template variable resolution
    #(
      "multiple indicators with template variable resolution",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("Foo SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            value.StringValue("production"),
          ),
          helpers.ValueTuple(
            "status",
            types.PrimitiveType(types.Boolean),
            value.BoolValue(True),
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
                  "denominator",
                  value.StringValue("avg:system.cpu{$$env->env$$}"),
                ),
                #(
                  "numerator",
                  value.StringValue(
                    "avg:system.cpu{$$env->env$$ AND $$status->status:not$$}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("Foo SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            value.StringValue("production"),
          ),
          helpers.ValueTuple(
            "status",
            types.PrimitiveType(types.Boolean),
            value.BoolValue(True),
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
                  "denominator",
                  value.StringValue("avg:system.cpu{env:production}"),
                ),
                #(
                  "numerator",
                  value.StringValue(
                    "avg:system.cpu{env:production AND !status:true}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("denominator", "avg:system.cpu{env:production}"),
            #("numerator", "avg:system.cpu{env:production AND !status:true}"),
          ]),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      )),
    ),
    // happy path - defaulted param with nil uses default value
    #(
      "defaulted param with nil uses default value",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            value.StringValue("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.NumericType(types.Integer)),
              "2500000000",
            )),
            value.NilValue,
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
                  "query",
                  value.StringValue("p75:rum.lcp.duration{$$env->env$$}"),
                ),
              ]),
            ),
          ),
          helpers.ValueTuple(
            "evaluation",
            types.PrimitiveType(types.String),
            value.StringValue("time_slice(query > $$threshold_in_ms$$ per 5m)"),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            value.StringValue("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.NumericType(types.Integer)),
              "2500000000",
            )),
            value.NilValue,
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
                  "query",
                  value.StringValue("p75:rum.lcp.duration{env:production}"),
                ),
              ]),
            ),
          ),
          helpers.ValueTuple(
            "evaluation",
            types.PrimitiveType(types.String),
            value.StringValue("time_slice(query > 2500000000 per 5m)"),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("query", "p75:rum.lcp.duration{env:production}"),
          ]),
          window_in_days: 30,
          evaluation: option.Some("time_slice(query > 2500000000 per 5m)"),
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      )),
    ),
    // happy path - refinement type with defaulted inner using nil gets default value
    #(
      "refinement type with defaulted inner using nil gets default value",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP SLO Refinement"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo_refinement",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            types.RefinementType(types.OneOf(
              types.ModifierType(types.Defaulted(
                types.PrimitiveType(types.String),
                "production",
              )),
              set.from_list(["production", "staging"]),
            )),
            value.NilValue,
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
                  "query",
                  value.StringValue(
                    "p75:rum.lcp.duration{$$env->environment$$}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP SLO Refinement"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo_refinement",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            types.RefinementType(types.OneOf(
              types.ModifierType(types.Defaulted(
                types.PrimitiveType(types.String),
                "production",
              )),
              set.from_list(["production", "staging"]),
            )),
            value.NilValue,
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
                  "query",
                  value.StringValue("p75:rum.lcp.duration{env:production}"),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("query", "p75:rum.lcp.duration{env:production}"),
          ]),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      )),
    ),
    // happy path - lcp_p75_latency style: multiple params, mix of defaulted and refinement types
    // Simulates: environment not provided (uses default "production"),
    // application_name not provided (uses default "member_portal"),
    // view_path provided explicitly
    #(
      "lcp_p75_latency style with mix of defaulted, refinement, and provided values",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP is Reasonable"),
          org_name: identifiers.OrgName("member_growth"),
          service_name: identifiers.ServiceName("member_portal"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("member"),
          misc: dict.new(),
        ),
        unique_identifier: "member_growth_member_portal_lcp_is_reasonable",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          // environment: Defaulted(String, production) { x | x in { production } } - NOT provided
          helpers.ValueTuple(
            "environment",
            types.RefinementType(types.OneOf(
              types.ModifierType(types.Defaulted(
                types.PrimitiveType(types.String),
                "production",
              )),
              set.from_list(["production"]),
            )),
            value.NilValue,
          ),
          // application_name: Defaulted(String, member_portal) - NOT provided
          helpers.ValueTuple(
            "application_name",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "member_portal",
            )),
            value.NilValue,
          ),
          // view_path: String - PROVIDED
          helpers.ValueTuple(
            "view_path",
            types.PrimitiveType(types.String),
            value.StringValue("/members/messages"),
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
                  "query",
                  value.StringValue(
                    "p75:rum.lcp.duration{$$application.name->application_name$$, $$env->environment$$, $$view.url_path_group->view_path$$}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("LCP is Reasonable"),
          org_name: identifiers.OrgName("member_growth"),
          service_name: identifiers.ServiceName("member_portal"),
          blueprint_name: identifiers.BlueprintName("lcp_p75_latency"),
          team_name: identifiers.TeamName("member"),
          misc: dict.new(),
        ),
        unique_identifier: "member_growth_member_portal_lcp_is_reasonable",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            types.RefinementType(types.OneOf(
              types.ModifierType(types.Defaulted(
                types.PrimitiveType(types.String),
                "production",
              )),
              set.from_list(["production"]),
            )),
            value.NilValue,
          ),
          helpers.ValueTuple(
            "application_name",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "member_portal",
            )),
            value.NilValue,
          ),
          helpers.ValueTuple(
            "view_path",
            types.PrimitiveType(types.String),
            value.StringValue("/members/messages"),
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
                  "query",
                  // All defaults resolved: application.name:member_portal, env:production, view.url_path_group:/members/messages
                  value.StringValue(
                    "p75:rum.lcp.duration{application.name:member_portal, env:production, view.url_path_group:/members/messages}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #(
              "query",
              "p75:rum.lcp.duration{application.name:member_portal, env:production, view.url_path_group:/members/messages}",
            ),
          ]),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Datadog),
      )),
    ),
  ]
  |> test_helpers.table_test_1(semantic_analyzer.resolve_indicators)
}

// TODO: resolve_vendor has been moved to IR builder level; update or remove these tests
// // ==== resolve_vendor ====
// // * ✅ happy path - known vendor, Honeycomb
// pub fn resolve_vendor_honeycomb_test() {
//   ...
// }

// ==== resolve_indicators ====
// * ✅ happy path - Honeycomb indicators pass through without template resolution
pub fn resolve_indicators_honeycomb_passthrough_test() {
  [
    #(
      "Honeycomb indicators pass through without template resolution",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("HC SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "hc_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_honeycomb),
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
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Honeycomb),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("HC SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "hc_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_honeycomb),
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
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Honeycomb),
      )),
    ),
  ]
  |> test_helpers.table_test_1(semantic_analyzer.resolve_indicators)
}

// TODO: resolve_vendor has been moved to IR builder level; update or remove these tests
// // ==== resolve_vendor ====
// // * ✅ happy path - known vendor, Dynatrace
// pub fn resolve_vendor_dynatrace_test() {
//   ...
// }

// ==== resolve_indicators ====
// * ✅ happy path - Dynatrace indicators pass through without template resolution
pub fn resolve_indicators_dynatrace_passthrough_test() {
  [
    #(
      "Dynatrace indicators pass through without template resolution",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("DT SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "dt_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_dynatrace),
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
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Dynatrace),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("DT SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "dt_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_dynatrace),
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
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.Dynatrace),
      )),
    ),
  ]
  |> test_helpers.table_test_1(semantic_analyzer.resolve_indicators)
}

// ==== resolve_intermediate_representations ====
// * ✅ happy path - mixed vendors (Datadog + Honeycomb) resolves both correctly
pub fn resolve_intermediate_representations_mixed_vendor_test() {
  let datadog_ir =
    ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("DD SLO"),
        org_name: identifiers.OrgName("test"),
        service_name: identifiers.ServiceName("service"),
        blueprint_name: identifiers.BlueprintName("test_blueprint"),
        team_name: identifiers.TeamName("test_team"),
        misc: dict.new(),
      ),
      unique_identifier: "dd_slo",
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          value.StringValue(constants.vendor_datadog),
        ),
        helpers.ValueTuple(
          "env",
          types.PrimitiveType(types.String),
          value.StringValue("staging"),
        ),
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          value.DictValue(
            dict.from_list([
              #("query_a", value.StringValue("avg:memory{$$env->env$$}")),
            ]),
          ),
        ),
      ],
      slo: ir.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.Some(vendor.Datadog),
    )

  let honeycomb_ir =
    ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("HC SLO"),
        org_name: identifiers.OrgName("test"),
        service_name: identifiers.ServiceName("service"),
        blueprint_name: identifiers.BlueprintName("test_blueprint"),
        team_name: identifiers.TeamName("test_team"),
        misc: dict.new(),
      ),
      unique_identifier: "hc_slo",
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          value.StringValue(constants.vendor_honeycomb),
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
      slo: ir.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.Some(vendor.Honeycomb),
    )

  [
    #(
      "mixed vendors (Datadog + Honeycomb) resolves both correctly",
      [datadog_ir, honeycomb_ir],
      Ok([
        ir.IntermediateRepresentation(
          metadata: ir.IntermediateRepresentationMetaData(
            friendly_label: identifiers.ExpectationLabel("DD SLO"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "dd_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              value.StringValue("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              value.DictValue(
                dict.from_list([
                  #("query_a", value.StringValue("avg:memory{env:staging}")),
                ]),
              ),
            ),
          ],
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_a", "avg:memory{env:staging}"),
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
            friendly_label: identifiers.ExpectationLabel("HC SLO"),
            org_name: identifiers.OrgName("test"),
            service_name: identifiers.ServiceName("service"),
            blueprint_name: identifiers.BlueprintName("test_blueprint"),
            team_name: identifiers.TeamName("test_team"),
            misc: dict.new(),
          ),
          unique_identifier: "hc_slo",
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              value.StringValue(constants.vendor_honeycomb),
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
          slo: ir.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
            depends_on: option.None,
          ),
          vendor: option.Some(vendor.Honeycomb),
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(
    semantic_analyzer.resolve_intermediate_representations,
  )
}

// ==== resolve_indicators ====
// * ✅ error - no vendor resolved returns SemanticAnalysisTemplateResolutionError
pub fn resolve_indicators_no_vendor_error_test() {
  let ir =
    ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("No Vendor SLO"),
        org_name: identifiers.OrgName("test"),
        service_name: identifiers.ServiceName("service"),
        blueprint_name: identifiers.BlueprintName("test_blueprint"),
        team_name: identifiers.TeamName("test_team"),
        misc: dict.new(),
      ),
      unique_identifier: "no_vendor_slo",
      values: [
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          value.DictValue(
            dict.from_list([
              #("query", value.StringValue("avg:system.cpu{env:prod}")),
            ]),
          ),
        ),
      ],
      slo: ir.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.None,
    )

  let assert Error(err) = semantic_analyzer.resolve_indicators(ir)
  err
  |> should.equal(errors.semantic_analysis_template_resolution_error(
    msg: "expectation 'test.test_team.service.No Vendor SLO' - no vendor resolved",
  ))
}

// ==== resolve_indicators ====
// * ✅ happy path - NewRelic indicators pass through without template resolution
pub fn resolve_indicators_newrelic_passthrough_test() {
  [
    #(
      "NewRelic indicators pass through without template resolution",
      ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("NR SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "nr_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_newrelic),
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
                  "good",
                  value.StringValue(
                    "FROM Transaction SELECT count(*) WHERE duration < 0.5",
                  ),
                ),
                #(
                  "valid",
                  value.StringValue("FROM Transaction SELECT count(*)"),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.NewRelic),
      ),
      Ok(ir.IntermediateRepresentation(
        metadata: ir.IntermediateRepresentationMetaData(
          friendly_label: identifiers.ExpectationLabel("NR SLO"),
          org_name: identifiers.OrgName("test"),
          service_name: identifiers.ServiceName("service"),
          blueprint_name: identifiers.BlueprintName("test_blueprint"),
          team_name: identifiers.TeamName("test_team"),
          misc: dict.new(),
        ),
        unique_identifier: "nr_slo",
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_newrelic),
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
                  "good",
                  value.StringValue(
                    "FROM Transaction SELECT count(*) WHERE duration < 0.5",
                  ),
                ),
                #(
                  "valid",
                  value.StringValue("FROM Transaction SELECT count(*)"),
                ),
              ]),
            ),
          ),
        ],
        slo: ir.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
          depends_on: option.None,
        ),
        vendor: option.Some(vendor.NewRelic),
      )),
    ),
  ]
  |> test_helpers.table_test_1(semantic_analyzer.resolve_indicators)
}

// ==== resolve_intermediate_representations ====
// * ✅ error - no vendor on SLO IR propagates through from_results
pub fn resolve_intermediate_representations_no_vendor_error_test() {
  let no_vendor_ir =
    ir.IntermediateRepresentation(
      metadata: ir.IntermediateRepresentationMetaData(
        friendly_label: identifiers.ExpectationLabel("Bad SLO"),
        org_name: identifiers.OrgName("test"),
        service_name: identifiers.ServiceName("service"),
        blueprint_name: identifiers.BlueprintName("test_blueprint"),
        team_name: identifiers.TeamName("test_team"),
        misc: dict.new(),
      ),
      unique_identifier: "bad_slo",
      values: [],
      slo: ir.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
        depends_on: option.None,
      ),
      vendor: option.None,
    )

  semantic_analyzer.resolve_intermediate_representations([no_vendor_ir])
  |> should.be_error()
}
