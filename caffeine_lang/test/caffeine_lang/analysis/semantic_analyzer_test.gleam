/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
/// Uses array-based test pattern for consistency.
import caffeine_lang/analysis/semantic_analyzer
import caffeine_lang/analysis/vendor
import caffeine_lang/common/constants
import caffeine_lang/common/helpers
import caffeine_lang/common/types
import gleam/dict
import gleam/dynamic
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("query_a"),
                  dynamic.string("avg:memory{$$env->env$$}"),
                ),
              ]),
            ),
          ],
          vendor: option.None,
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              types.PrimitiveType(types.String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("query_b"),
                  dynamic.string("sum:requests{$$region->region$$}"),
                ),
              ]),
            ),
          ],
          vendor: option.None,
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("query_a"),
                  dynamic.string("avg:memory{env:staging}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              types.PrimitiveType(types.String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("query_b"),
                  dynamic.string("sum:requests{region:us-east}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
        ],
        vendor: option.None,
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            types.PrimitiveType(types.Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("denominator"),
                dynamic.string("avg:system.cpu{$$env->env$$}"),
              ),
              #(
                dynamic.string("numerator"),
                dynamic.string(
                  "avg:system.cpu{$$env->env$$ AND $$status->status:not$$}",
                ),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            types.PrimitiveType(types.Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("denominator"),
                dynamic.string("avg:system.cpu{env:production}"),
              ),
              #(
                dynamic.string("numerator"),
                dynamic.string(
                  "avg:system.cpu{env:production AND !status:True}",
                ),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.NumericType(types.Integer)),
              "2500000000",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{$$env->env$$}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "evaluation",
            types.PrimitiveType(types.String),
            dynamic.string("time_slice(query > $$threshold_in_ms$$ per 5m)"),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            types.PrimitiveType(types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.NumericType(types.Integer)),
              "2500000000",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{env:production}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "evaluation",
            types.PrimitiveType(types.String),
            dynamic.string("time_slice(query > 2500000000 per 5m)"),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
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
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{$$env->environment$$}"),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
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
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{env:production}"),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
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
            dynamic.nil(),
          ),
          // application_name: Defaulted(String, member_portal) - NOT provided
          helpers.ValueTuple(
            "application_name",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "member_portal",
            )),
            dynamic.nil(),
          ),
          // view_path: String - PROVIDED
          helpers.ValueTuple(
            "view_path",
            types.PrimitiveType(types.String),
            dynamic.string("/members/messages"),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string(
                  "p75:rum.lcp.duration{$$application.name->application_name$$, $$env->environment$$, $$view.url_path_group->view_path$$}",
                ),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_datadog),
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
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "application_name",
            types.ModifierType(types.Defaulted(
              types.PrimitiveType(types.String),
              "member_portal",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "view_path",
            types.PrimitiveType(types.String),
            dynamic.string("/members/messages"),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                // All defaults resolved: application.name:member_portal, env:production, view.url_path_group:/members/messages
                dynamic.string(
                  "p75:rum.lcp.duration{application.name:member_portal, env:production, view.url_path_group:/members/messages}",
                ),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_honeycomb),
          ),
        ],
        vendor: option.None,
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_honeycomb),
          ),
        ],
        vendor: option.Some(vendor.Honeycomb),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_honeycomb),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("sli"),
                dynamic.string("LT($\"status_code\", 500)"),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Honeycomb),
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
        artifact_refs: ["SLO"],
        values: [
          helpers.ValueTuple(
            "vendor",
            types.PrimitiveType(types.String),
            dynamic.string(constants.vendor_honeycomb),
          ),
          helpers.ValueTuple(
            "indicators",
            types.CollectionType(types.Dict(
              types.PrimitiveType(types.String),
              types.PrimitiveType(types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("sli"),
                dynamic.string("LT($\"status_code\", 500)"),
              ),
            ]),
          ),
        ],
        vendor: option.Some(vendor.Honeycomb),
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
      artifact_refs: ["SLO"],
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          dynamic.string(constants.vendor_datadog),
        ),
        helpers.ValueTuple(
          "env",
          types.PrimitiveType(types.String),
          dynamic.string("staging"),
        ),
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          dynamic.properties([
            #(
              dynamic.string("query_a"),
              dynamic.string("avg:memory{$$env->env$$}"),
            ),
          ]),
        ),
      ],
      vendor: option.None,
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
      artifact_refs: ["SLO"],
      values: [
        helpers.ValueTuple(
          "vendor",
          types.PrimitiveType(types.String),
          dynamic.string(constants.vendor_honeycomb),
        ),
        helpers.ValueTuple(
          "indicators",
          types.CollectionType(types.Dict(
            types.PrimitiveType(types.String),
            types.PrimitiveType(types.String),
          )),
          dynamic.properties([
            #(
              dynamic.string("sli"),
              dynamic.string("LT($\"status_code\", 500)"),
            ),
          ]),
        ),
      ],
      vendor: option.None,
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              types.PrimitiveType(types.String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("query_a"),
                  dynamic.string("avg:memory{env:staging}"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Datadog),
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
          artifact_refs: ["SLO"],
          values: [
            helpers.ValueTuple(
              "vendor",
              types.PrimitiveType(types.String),
              dynamic.string(constants.vendor_honeycomb),
            ),
            helpers.ValueTuple(
              "indicators",
              types.CollectionType(types.Dict(
                types.PrimitiveType(types.String),
                types.PrimitiveType(types.String),
              )),
              dynamic.properties([
                #(
                  dynamic.string("sli"),
                  dynamic.string("LT($\"status_code\", 500)"),
                ),
              ]),
            ),
          ],
          vendor: option.Some(vendor.Honeycomb),
        ),
      ]),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(
    semantic_analyzer.resolve_intermediate_representations,
  )
}
