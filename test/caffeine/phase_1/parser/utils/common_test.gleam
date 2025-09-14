import caffeine/phase_1/parser/utils/common
import glaml

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
