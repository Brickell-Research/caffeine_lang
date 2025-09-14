import caffeine/phase_1/parser/specification/unresolved_sli_types_specification
import caffeine/types/specification_types.{SliTypeUnresolved}

pub fn parse_sli_types_test() {
  let expected_sli_types = [
    SliTypeUnresolved(name: "latency", query_template_type: "good_over_bad"),
    SliTypeUnresolved(name: "error_rate", query_template_type: "good_over_bad"),
  ]

  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types.yaml",
    )
  assert actual == Ok(expected_sli_types)
}

pub fn parse_sli_types_missing_name_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}

pub fn parse_sli_types_missing_query_template_test() {
  let actual =
    unresolved_sli_types_specification.parse_unresolved_sli_types_specification(
      "test/artifacts/specifications/sli_types_missing_query_template.yaml",
    )
  assert actual == Error("Missing query_template_type")
}
