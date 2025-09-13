import caffeine/intermediate_representation
import caffeine/parser/common
import caffeine/parser/instantiation
import caffeine/parser/specification
import glaml
import gleam/dict

pub fn parse_instantiation_no_slos_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/less_reliable_service.yaml",
    )
  assert actual == Error("Empty YAML file")
}

pub fn parse_instantiation_multiple_slos_test() {
  let expected_slo =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[200, 201]")]),
      threshold: 99.5,
      sli_type: "http_status_code",
      service_name: "reliable_service",
    )

  let expected_slo_2 =
    intermediate_representation.Slo(
      filters: dict.from_list([#("acceptable_status_codes", "[203, 204]")]),
      threshold: 99.99,
      sli_type: "http_status_code",
      service_name: "reliable_service",
    )

  let expected_team =
    intermediate_representation.Team(name: "platform", slos: [
      expected_slo,
      expected_slo_2,
    ])

  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service.yaml",
    )
  assert actual == Ok(expected_team)
}

pub fn parse_instantiation_missing_sli_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_sli_type.yaml",
    )
  assert actual == Error("Missing sli_type")
}

pub fn parse_instantiation_missing_filters_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_filters.yaml",
    )
  assert actual == Error("Missing filters")
}

pub fn parse_instantiation_missing_threshold_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_threshold.yaml",
    )
  assert actual == Error("Missing threshold")
}

pub fn parse_instantiation_missing_slos_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_missing_slos.yaml",
    )
  assert actual == Error("Missing SLOs")
}

pub fn parse_instantiation_invalid_threshold_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    )
  assert actual == Error("Expected threshold to be a float")
}

pub fn parse_instantiation_invalid_sli_type_type_test() {
  let actual =
    instantiation.parse_instantiation(
      "test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    )
  assert actual == Error("Expected sli_type to be a string")
}

pub fn extract_some_node_by_key_exists_test() {
  let actual =
    common.extract_some_node_by_key(
      glaml.NodeMap([#(glaml.NodeStr("key"), glaml.NodeStr("value"))]),
      "key",
    )
  assert actual == Ok(glaml.NodeStr("value"))
}

pub fn extract_some_node_by_key_does_not_exist_test() {
  let actual =
    common.extract_some_node_by_key(
      glaml.NodeMap([#(glaml.NodeStr("key"), glaml.NodeStr("value"))]),
      "key_not_found",
    )
  assert actual == Error("Missing key_not_found")
}

pub fn extract_service_and_team_name_from_file_path_test() {
  let actual =
    common.extract_service_and_team_name_from_file_path(
      "test/artifacts/platform/reliable_service.yaml",
    )
  assert actual == Ok(#("platform", "reliable_service"))
}

pub fn extract_service_and_team_name_from_file_path_invalid_test() {
  let actual =
    common.extract_service_and_team_name_from_file_path("reliable_service.yaml")
  assert actual
    == Error("Invalid file path: expected at least 'team/service.yaml'")
}

pub fn parse_yaml_file_test() {
  let actual =
    common.parse_yaml_file("test/artifacts/platform/simple_yaml_load_test.yaml")
  assert actual
    == Ok([
      glaml.Document(
        glaml.NodeMap([#(glaml.NodeStr("key"), glaml.NodeStr("value"))]),
      ),
    ])
}

pub fn parse_yaml_file_invalid_test() {
  let actual =
    common.parse_yaml_file("test/artifacts/platform/non_existent.yaml")
  assert actual
    == Error(
      "Failed to parse YAML file: test/artifacts/platform/non_existent.yaml",
    )
}

pub fn parse_services_test() {
  let expected_services = [
    specification.ServicePreSugared(name: "reliable_service", sli_types: [
      "latency",
      "error_rate",
    ]),
    specification.ServicePreSugared(name: "unreliable_service", sli_types: [
      "error_rate",
    ]),
  ]

  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services.yaml",
    )
  assert actual == Ok(expected_services)
}

pub fn parse_services_missing_sli_types_test() {
  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services_missing_sli_types.yaml",
    )
  assert actual == Error("Missing sli_types")
}

pub fn parse_services_missing_name_test() {
  let actual =
    specification.parse_services_specification(
      "test/artifacts/specifications/services_missing_name.yaml",
    )
  assert actual == Error("Missing name")
}

pub fn parse_sli_filters_test() {
  let expected_sli_filters = [
    intermediate_representation.SliFilter(
      attribute_name: "team_name",
      attribute_type: intermediate_representation.String,
      required: True,
    ),
    intermediate_representation.SliFilter(
      attribute_name: "number_of_users",
      attribute_type: intermediate_representation.Integer,
      required: True,
    ),
    intermediate_representation.SliFilter(
      attribute_name: "accepted_status_codes",
      attribute_type: intermediate_representation.List(
        intermediate_representation.String,
      ),
      required: False,
    ),
  ]

  let actual =
    specification.parse_sli_filters_specification(
      "test/artifacts/specifications/sli_filters.yaml",
    )
  assert actual == Ok(expected_sli_filters)
}

pub fn parse_sli_filters_missing_attribute_type_test() {
  let actual =
    specification.parse_sli_filters_specification(
      "test/artifacts/specifications/sli_filters_missing_attribute_type.yaml",
    )
  assert actual == Error("Missing attribute_type")
}

pub fn parse_sli_filters_missing_attribute_required_test() {
  let actual =
    specification.parse_sli_filters_specification(
      "test/artifacts/specifications/sli_filters_missing_attribute_required.yaml",
    )
  assert actual == Error("Missing required")
}

pub fn parse_sli_filters_missing_attribute_name_test() {
  let actual =
    specification.parse_sli_filters_specification(
      "test/artifacts/specifications/sli_filters_missing_attribute_name.yaml",
    )
  assert actual == Error("Missing attribute_name")
}

pub fn parse_sli_filters_unrecognized_attribute_type_test() {
  let actual =
    specification.parse_sli_filters_specification(
      "test/artifacts/specifications/sli_filters_unrecognized_attribute_type.yaml",
    )
  assert actual == Error("Unknown attribute type: LargeNumber")
}
