/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
/// Uses array-based test pattern for consistency.
import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/constants
import caffeine_lang/common/helpers
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/option
import gleam/set
import test_helpers

// ==== resolve_intermediate_representations ====
// * ✅ happy path - two IRs with vendor resolution and query template resolution
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
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
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
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
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
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
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
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              accepted_types.PrimitiveType(primitive_types.String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "queries",
              accepted_types.CollectionType(collection_types.Dict(
                accepted_types.PrimitiveType(primitive_types.String),
                accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_vendor)
}

// ==== resolve_queries ====
// * ✅ happy path - multiple queries with template variable resolution
// * ✅ happy path - defaulted param with nil uses default value
// * ✅ happy path - refinement type with defaulted inner using nil gets default value
// * ✅ happy path - lcp_p75_latency style with mix of defaulted, refinement, and provided values
pub fn resolve_queries_test() {
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            accepted_types.PrimitiveType(primitive_types.Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            accepted_types.PrimitiveType(primitive_types.Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.NumericType(numeric_types.Integer)),
              "2500000000",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{$$env->env$$}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "value",
            accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.NumericType(numeric_types.Integer)),
              "2500000000",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{env:production}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "value",
            accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            accepted_types.RefinementType(
              refinement_types.OneOf(
                accepted_types.ModifierType(modifier_types.Defaulted(
                  accepted_types.PrimitiveType(primitive_types.String),
                  "production",
                )),
                set.from_list(["production", "staging"]),
              ),
            ),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
            )),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string(
                  "p75:rum.lcp.duration{$$env->environment$$}",
                ),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            accepted_types.RefinementType(
              refinement_types.OneOf(
                accepted_types.ModifierType(modifier_types.Defaulted(
                  accepted_types.PrimitiveType(primitive_types.String),
                  "production",
                )),
                set.from_list(["production", "staging"]),
              ),
            ),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          // environment: Defaulted(String, production) { x | x in { production } } - NOT provided
          helpers.ValueTuple(
            "environment",
            accepted_types.RefinementType(
              refinement_types.OneOf(
                accepted_types.ModifierType(modifier_types.Defaulted(
                  accepted_types.PrimitiveType(primitive_types.String),
                  "production",
                )),
                set.from_list(["production"]),
              ),
            ),
            dynamic.nil(),
          ),
          // application_name: Defaulted(String, member_portal) - NOT provided
          helpers.ValueTuple(
            "application_name",
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.String),
              "member_portal",
            )),
            dynamic.nil(),
          ),
          // view_path: String - PROVIDED
          helpers.ValueTuple(
            "view_path",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("/members/messages"),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
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
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "environment",
            accepted_types.RefinementType(
              refinement_types.OneOf(
                accepted_types.ModifierType(modifier_types.Defaulted(
                  accepted_types.PrimitiveType(primitive_types.String),
                  "production",
                )),
                set.from_list(["production"]),
              ),
            ),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "application_name",
            accepted_types.ModifierType(modifier_types.Defaulted(
              accepted_types.PrimitiveType(primitive_types.String),
              "member_portal",
            )),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "view_path",
            accepted_types.PrimitiveType(primitive_types.String),
            dynamic.string("/members/messages"),
          ),
          helpers.ValueTuple(
            "queries",
            accepted_types.CollectionType(collection_types.Dict(
              accepted_types.PrimitiveType(primitive_types.String),
              accepted_types.PrimitiveType(primitive_types.String),
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
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_queries)
}
