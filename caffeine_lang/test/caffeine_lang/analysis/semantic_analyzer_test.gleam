/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
/// Uses array-based test pattern for consistency.
import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/constants
import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/option
import gleam/set
import test_helpers

// ==== resolve_intermediate_representations ====
// * ✅ happy path - two IRs with vendor resolution and indicator template resolution
pub fn resolve_intermediate_representations_test() {
  [
    // happy path - two IRs with vendor resolution and query template resolution
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "SLO One",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "slo_one",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.NoVendor,
        ),
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "SLO Two",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "slo_two",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.NoVendor,
        ),
      ],
      Ok([
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "SLO One",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "slo_one",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_a", "avg:memory{env:staging}"),
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
            friendly_label: "SLO Two",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "slo_two",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_b", "sum:requests{region:us-east}"),
            ]),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_intermediate_representations,
  )
}

// ==== resolve_vendor ====
// * ✅ happy path - known vendor, Datadog
pub fn resolve_vendor_test() {
  [
    // happy path - known vendor, Datadog
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.NoVendor,
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_datadog),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_vendor)
}

// ==== resolve_indicators ====
// * ✅ happy path - multiple indicators with template variable resolution
// * ✅ happy path - defaulted param with nil uses default value
// * ✅ happy path - refinement type with defaulted inner using nil gets default value
// * ✅ happy path - lcp_p75_latency style with mix of defaulted, refinement, and provided values
pub fn resolve_indicators_test() {
  [
    // happy path - multiple queries with template variable resolution
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
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
                    "avg:system.cpu{env:production AND !status:True}",
                  ),
                ),
              ]),
            ),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("denominator", "avg:system.cpu{env:production}"),
            #("numerator", "avg:system.cpu{env:production AND !status:True}"),
          ]),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      )),
    ),
    // happy path - defaulted param with nil uses default value
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "lcp_p75_latency",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "lcp_p75_latency",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("query", "p75:rum.lcp.duration{env:production}"),
          ]),
          window_in_days: 30,
          evaluation: option.Some("time_slice(query > 2500000000 per 5m)"),
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      )),
    ),
    // happy path - refinement type with defaulted inner using nil gets default value
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP SLO Refinement",
          org_name: "test",
          service_name: "service",
          blueprint_name: "lcp_p75_latency",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo_refinement",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP SLO Refinement",
          org_name: "test",
          service_name: "service",
          blueprint_name: "lcp_p75_latency",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "lcp_slo_refinement",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.from_list([
            #("query", "p75:rum.lcp.duration{env:production}"),
          ]),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      )),
    ),
    // happy path - lcp_p75_latency style: multiple params, mix of defaulted and refinement types
    // Simulates: environment not provided (uses default "production"),
    // application_name not provided (uses default "member_portal"),
    // view_path provided explicitly
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP is Reasonable",
          org_name: "member_growth",
          service_name: "member_portal",
          blueprint_name: "lcp_p75_latency",
          team_name: "member",
          misc: dict.new(),
        ),
        unique_identifier: "member_growth_member_portal_lcp_is_reasonable",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "LCP is Reasonable",
          org_name: "member_growth",
          service_name: "member_portal",
          blueprint_name: "lcp_p75_latency",
          team_name: "member",
          misc: dict.new(),
        ),
        unique_identifier: "member_growth_member_portal_lcp_is_reasonable",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
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
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Datadog),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_indicators,
  )
}

// ==== resolve_vendor ====
// * ✅ happy path - known vendor, Honeycomb
pub fn resolve_vendor_honeycomb_test() {
  [
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_honeycomb),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.NoVendor,
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_honeycomb),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_vendor)
}

// ==== resolve_indicators ====
// * ✅ happy path - Honeycomb indicators pass through without template resolution
pub fn resolve_indicators_honeycomb_passthrough_test() {
  [
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "HC SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "hc_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "HC SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "hc_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_indicators,
  )
}

// ==== resolve_vendor ====
// * ✅ happy path - known vendor, Dynatrace
pub fn resolve_vendor_dynatrace_test() {
  [
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_dynatrace),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.NoVendor,
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "Foo SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "foo",
        artifact_refs: [SLO],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            value.StringValue(constants.vendor_dynatrace),
          ),
        ],
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Dynatrace),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_vendor)
}

// ==== resolve_indicators ====
// * ✅ happy path - Dynatrace indicators pass through without template resolution
pub fn resolve_indicators_dynatrace_passthrough_test() {
  [
    #(
      semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "DT SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "dt_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Dynatrace),
      ),
      Ok(semantic_analyzer.IntermediateRepresentation(
        metadata: semantic_analyzer.IntermediateRepresentationMetaData(
          friendly_label: "DT SLO",
          org_name: "test",
          service_name: "service",
          blueprint_name: "test_blueprint",
          team_name: "test_team",
          misc: dict.new(),
        ),
        unique_identifier: "dt_slo",
        artifact_refs: [SLO],
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
        artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
          threshold: 0.0,
          indicators: dict.new(),
          window_in_days: 30,
          evaluation: option.None,
          tags: [],
          runbook: option.None,
        )),
        vendor: semantic_analyzer.ResolvedVendor(vendor.Dynatrace),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_indicators,
  )
}

// ==== resolve_intermediate_representations ====
// * ✅ happy path - mixed vendors (Datadog + Honeycomb) resolves both correctly
pub fn resolve_intermediate_representations_mixed_vendor_test() {
  let datadog_ir =
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "DD SLO",
        org_name: "test",
        service_name: "service",
        blueprint_name: "test_blueprint",
        team_name: "test_team",
        misc: dict.new(),
      ),
      unique_identifier: "dd_slo",
      artifact_refs: [SLO],
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
      artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: semantic_analyzer.NoVendor,
    )

  let honeycomb_ir =
    semantic_analyzer.IntermediateRepresentation(
      metadata: semantic_analyzer.IntermediateRepresentationMetaData(
        friendly_label: "HC SLO",
        org_name: "test",
        service_name: "service",
        blueprint_name: "test_blueprint",
        team_name: "test_team",
        misc: dict.new(),
      ),
      unique_identifier: "hc_slo",
      artifact_refs: [SLO],
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
      artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
        threshold: 0.0,
        indicators: dict.new(),
        window_in_days: 30,
        evaluation: option.None,
        tags: [],
        runbook: option.None,
      )),
      vendor: semantic_analyzer.NoVendor,
    )

  [
    #(
      [datadog_ir, honeycomb_ir],
      Ok([
        semantic_analyzer.IntermediateRepresentation(
          metadata: semantic_analyzer.IntermediateRepresentationMetaData(
            friendly_label: "DD SLO",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "dd_slo",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.from_list([
              #("query_a", "avg:memory{env:staging}"),
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
            friendly_label: "HC SLO",
            org_name: "test",
            service_name: "service",
            blueprint_name: "test_blueprint",
            team_name: "test_team",
            misc: dict.new(),
          ),
          unique_identifier: "hc_slo",
          artifact_refs: [SLO],
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
          artifact_data: semantic_analyzer.slo_only(semantic_analyzer.SloFields(
            threshold: 0.0,
            indicators: dict.new(),
            window_in_days: 30,
            evaluation: option.None,
            tags: [],
            runbook: option.None,
          )),
          vendor: semantic_analyzer.ResolvedVendor(vendor.Honeycomb),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_intermediate_representations,
  )
}
