import caffeine_lang_v2/common/helpers.{type AcceptedTypes}
import gleam/dynamic.{type Dynamic}

pub type ValueTuple {
  ValueTuple(label: String, typ: AcceptedTypes, value: Dynamic)
}

pub type IntermediateRepresentation {
  IntermediateRepresentation(
    expectation_name: String,
    artifact_ref: String,
    values: List(ValueTuple),
  )
}
