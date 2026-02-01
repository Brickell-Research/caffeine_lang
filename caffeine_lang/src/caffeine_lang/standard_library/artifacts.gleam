/// Let's all be honest, raw structures here feels a bit icky. However, we used to have a bunch of real
/// parser and semantic analysis logic in its place that just, on compile time, consumed a raw json
/// hardcoded string. That's way more offensive. We will work towards a better state, just know that even
/// in its existing offensive state right now (02/01/2026), it's much better than it was before.
/// - Rob
import caffeine_lang/common/accepted_types.{
  CollectionType, ModifierType, PrimitiveType, RefinementType,
}
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/common/semantic_types
import caffeine_lang/parser/artifacts.{
  type Artifact, Artifact, DependencyRelations, ParamInfo, SLO,
}
import gleam/dict
import gleam/set

/// Returns the hardcoded standard library artifacts.
pub fn standard_library() -> List(Artifact) {
  [slo_artifact(), dependency_relations_artifact()]
}

fn slo_artifact() -> Artifact {
  Artifact(
    type_: SLO,
    description: "A Service Level Objective that monitors a metric query against a threshold over a rolling window.",
    params: dict.from_list([
      #(
        "threshold",
        ParamInfo(
          type_: RefinementType(refinement_types.InclusiveRange(
            PrimitiveType(primitive_types.NumericType(numeric_types.Float)),
            "0.0",
            "100.0",
          )),
          description: "Target percentage (e.g., 99.9)",
        ),
      ),
      #(
        "window_in_days",
        ParamInfo(
          type_: ModifierType(modifier_types.Defaulted(
            PrimitiveType(primitive_types.NumericType(numeric_types.Integer)),
            "30",
          )),
          description: "Rolling window for measurement",
        ),
      ),
      #(
        "indicators",
        ParamInfo(
          type_: CollectionType(collection_types.Dict(
            PrimitiveType(primitive_types.String),
            PrimitiveType(primitive_types.String),
          )),
          description: "Named SLI measurement expressions",
        ),
      ),
      #(
        "evaluation",
        ParamInfo(
          type_: PrimitiveType(primitive_types.String),
          description: "How to evaluate indicators as an SLI",
        ),
      ),
      #(
        "vendor",
        ParamInfo(
          type_: RefinementType(refinement_types.OneOf(
            PrimitiveType(primitive_types.String),
            set.from_list(["datadog", "honeycomb"]),
          )),
          description: "Observability platform",
        ),
      ),
      #(
        "tags",
        ParamInfo(
          type_: ModifierType(
            modifier_types.Optional(
              CollectionType(collection_types.Dict(
                PrimitiveType(primitive_types.String),
                PrimitiveType(primitive_types.String),
              )),
            ),
          ),
          description: "An optional set of tags to append to the SLO artifact",
        ),
      ),
      #(
        "runbook",
        ParamInfo(
          type_: ModifierType(
            modifier_types.Optional(
              PrimitiveType(primitive_types.SemanticType(semantic_types.URL)),
            ),
          ),
          description: "An optional runbook URL surfaced via the SLO description",
        ),
      ),
    ]),
  )
}

fn dependency_relations_artifact() -> Artifact {
  Artifact(
    type_: DependencyRelations,
    description: "Declares soft and hard dependencies between services for dependency mapping.",
    params: dict.from_list([
      #(
        "relations",
        ParamInfo(
          type_: CollectionType(collection_types.Dict(
            RefinementType(refinement_types.OneOf(
              PrimitiveType(primitive_types.String),
              set.from_list(["soft", "hard"]),
            )),
            CollectionType(
              collection_types.List(PrimitiveType(primitive_types.String)),
            ),
          )),
          description: "Map of dependency type to list of service names",
        ),
      ),
    ]),
  )
}
