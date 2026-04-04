/// Let's all be honest, raw structures here feels a bit icky. However, we used to have a bunch of real
/// parser and semantic analysis logic in its place that just, on compile time, consumed a raw json
/// hardcoded string. That's way more offensive. We will work towards a better state, just know that even
/// in its existing offensive state right now (02/01/2026), it's much better than it was before.
/// - Rob
import caffeine_lang/linker/artifacts.{type ParamInfo, ParamInfo}
import caffeine_lang/types.{
  CollectionType, Defaulted, Dict, InclusiveRange, Integer, List as ListType,
  ModifierType, NumericType, Optional, Percentage, PrimitiveType, RecordType,
  RefinementType, SemanticType, String as StringType, URL,
}
import gleam/dict

/// Returns the hardcoded standard library SLO params.
pub fn slo_params() -> dict.Dict(String, ParamInfo) {
  dict.from_list([
    #(
      "threshold",
      ParamInfo(
        type_: PrimitiveType(NumericType(Percentage)),
        description: "Target percentage (e.g., 99.9%)",
      ),
    ),
    #(
      "window_in_days",
      ParamInfo(
        type_: ModifierType(Defaulted(
          RefinementType(InclusiveRange(
            PrimitiveType(NumericType(Integer)),
            "1",
            "90",
          )),
          "30",
        )),
        description: "Rolling window for measurement (1-90 days)",
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
    #(
      "depends_on",
      ParamInfo(
        type_: ModifierType(
          Optional(
            RecordType(
              dict.from_list([
                #(
                  "hard",
                  ModifierType(
                    Optional(
                      CollectionType(ListType(PrimitiveType(StringType))),
                    ),
                  ),
                ),
                #(
                  "soft",
                  ModifierType(
                    Optional(
                      CollectionType(ListType(PrimitiveType(StringType))),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        description: "Optional soft and hard dependency declarations for dependency mapping",
      ),
    ),
  ])
}
