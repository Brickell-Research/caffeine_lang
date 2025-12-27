/// Most of these tests are just integration tests so we'll focus mostly
/// just on the happy path to avoid duplicative testing.
/// Uses array-based test pattern for consistency.
import caffeine_lang/common/accepted_types.{
  Boolean, CollectionType, Defaulted, Dict, Integer, ModifierType, PrimitiveType,
  String,
}
import caffeine_lang/common/constants
import caffeine_lang/common/helpers
import caffeine_lang/middle_end/semantic_analyzer
import caffeine_lang/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/option
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
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              PrimitiveType(String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              PrimitiveType(String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "queries",
              CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              PrimitiveType(String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              PrimitiveType(String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "queries",
              CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              PrimitiveType(String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "env",
              PrimitiveType(String),
              dynamic.string("staging"),
            ),
            helpers.ValueTuple(
              "queries",
              CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
          artifact_ref: "SLO",
          values: [
            helpers.ValueTuple(
              "vendor",
              PrimitiveType(String),
              dynamic.string(constants.vendor_datadog),
            ),
            helpers.ValueTuple(
              "region",
              PrimitiveType(String),
              dynamic.string("us-east"),
            ),
            helpers.ValueTuple(
              "queries",
              CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            PrimitiveType(String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            PrimitiveType(Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            PrimitiveType(String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "status",
            PrimitiveType(Boolean),
            dynamic.bool(True),
          ),
          helpers.ValueTuple(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            PrimitiveType(String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            ModifierType(Defaulted(PrimitiveType(Integer), "2500000000")),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{$$env->env$$}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "value",
            PrimitiveType(String),
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
        artifact_ref: "SLO",
        values: [
          helpers.ValueTuple(
            "vendor",
            PrimitiveType(String),
            dynamic.string(constants.vendor_datadog),
          ),
          helpers.ValueTuple(
            "env",
            PrimitiveType(String),
            dynamic.string("production"),
          ),
          helpers.ValueTuple(
            "threshold_in_ms",
            ModifierType(Defaulted(PrimitiveType(Integer), "2500000000")),
            dynamic.nil(),
          ),
          helpers.ValueTuple(
            "queries",
            CollectionType(Dict(PrimitiveType(String), PrimitiveType(String))),
            dynamic.properties([
              #(
                dynamic.string("query"),
                dynamic.string("p75:rum.lcp.duration{env:production}"),
              ),
            ]),
          ),
          helpers.ValueTuple(
            "value",
            PrimitiveType(String),
            dynamic.string("time_slice(query > 2500000000 per 5m)"),
          ),
        ],
        vendor: option.Some(vendor.Datadog),
      )),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(semantic_analyzer.resolve_queries)
}
