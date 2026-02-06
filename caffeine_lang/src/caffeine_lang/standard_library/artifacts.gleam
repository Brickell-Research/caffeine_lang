/// Let's all be honest, raw structures here feels a bit icky. However, we used to have a bunch of real
/// parser and semantic analysis logic in its place that just, on compile time, consumed a raw json
/// hardcoded string. That's way more offensive. We will work towards a better state, just know that even
/// in its existing offensive state right now (02/01/2026), it's much better than it was before.
/// - Rob
import caffeine_lang/constants
import caffeine_lang/linker/artifacts.{
  type Artifact, Artifact, DependencyRelations, ParamInfo, SLO,
}
import caffeine_lang/types.{
  CollectionType, Defaulted, Dict, Float, InclusiveRange, Integer,
  List as ListType, ModifierType, NumericType, OneOf, Optional, PrimitiveType,
  RefinementType, SemanticType, String as StringType, URL,
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
          type_: RefinementType(InclusiveRange(
            PrimitiveType(NumericType(Float)),
            "0.0",
            "100.0",
          )),
          description: "Target percentage (e.g., 99.9)",
        ),
      ),
      #(
        "window_in_days",
        ParamInfo(
          type_: ModifierType(Defaulted(
            PrimitiveType(NumericType(Integer)),
            "30",
          )),
          description: "Rolling window for measurement",
        ),
      ),
      #(
        "indicators",
        ParamInfo(
          type_: CollectionType(Dict(
            PrimitiveType(StringType),
            PrimitiveType(StringType),
          )),
          description: "Named SLI measurement expressions",
        ),
      ),
      #(
        "evaluation",
        ParamInfo(
          type_: PrimitiveType(StringType),
          description: "How to evaluate indicators as an SLI",
        ),
      ),
      #(
        "vendor",
        ParamInfo(
          type_: RefinementType(OneOf(
            PrimitiveType(StringType),
            set.from_list([
              constants.vendor_datadog,
              constants.vendor_honeycomb,
              constants.vendor_dynatrace,
            ]),
          )),
          description: "Observability platform",
        ),
      ),
      #(
        "tags",
        ParamInfo(
          type_: ModifierType(
            Optional(
              CollectionType(Dict(
                PrimitiveType(StringType),
                PrimitiveType(StringType),
              )),
            ),
          ),
          description: "An optional set of tags to append to the SLO artifact",
        ),
      ),
      #(
        "runbook",
        ParamInfo(
          type_: ModifierType(Optional(PrimitiveType(SemanticType(URL)))),
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
          type_: CollectionType(Dict(
            RefinementType(OneOf(
              PrimitiveType(StringType),
              set.from_list(["soft", "hard"]),
            )),
            CollectionType(ListType(PrimitiveType(StringType))),
          )),
          description: "Map of dependency type to list of service names",
        ),
      ),
    ]),
  )
}
