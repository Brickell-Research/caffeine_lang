import glaml_extended
import gleam/dict
import gleeunit/should

// Helper function to parse YAML string to root node
fn yaml_to_root(yaml_str: String) -> glaml_extended.Node {
  let assert Ok([doc]) = glaml_extended.parse_string(yaml_str)
  glaml_extended.document_root(doc)
}

pub fn iteratively_parse_collection_success_test() {
  let root = yaml_to_root("services:\n  - name: service1\n  - name: service2")
  let parse_service = fn(node, _params) {
    glaml_extended.extract_string_from_node(node, "name")
  }
  glaml_extended.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "services",
  )
  |> should.equal(Ok(["service1", "service2"]))
}

pub fn iteratively_parse_collection_missing_key_test() {
  let root = yaml_to_root("services:\n  - name: service1")
  let parse_service = fn(node, _params) {
    glaml_extended.extract_string_from_node(node, "name")
  }
  glaml_extended.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "missing",
  )
  |> should.equal(Error("Missing missing"))
}

pub fn iteratively_parse_collection_single_item_test() {
  let root = yaml_to_root("services:\n  - name: only_service")
  let parse_service = fn(node, _params) {
    glaml_extended.extract_string_from_node(node, "name")
  }
  glaml_extended.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "services",
  )
  |> should.equal(Ok(["only_service"]))
}

pub fn iteratively_parse_collection_parse_error_test() {
  let root = yaml_to_root("services:\n  - name: service1\n  - other: no_name")
  let parse_service = fn(node, _params) {
    glaml_extended.extract_string_from_node(node, "name")
  }
  glaml_extended.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "services",
  )
  |> should.equal(Error("Missing name"))
}

pub fn iteratively_parse_collection_with_params_test() {
  let root = yaml_to_root("services:\n  - name: service1\n  - name: service2")
  let params = dict.from_list([#("prefix", "svc_")])
  let parse_service = fn(node, p) {
    let assert Ok(name) = glaml_extended.extract_string_from_node(node, "name")
    let assert Ok(prefix) = dict.get(p, "prefix")
    Ok(prefix <> name)
  }
  glaml_extended.iteratively_parse_collection(
    root,
    params,
    parse_service,
    "services",
  )
  |> should.equal(Ok(["svc_service1", "svc_service2"]))
}

pub fn iteratively_parse_collection_with_no_content_test() {
  let root = yaml_to_root("services:")
  let params = dict.new()
  let parse_service = fn(node, p) {
    let assert Ok(name) = glaml_extended.extract_string_from_node(node, "name")
    let assert Ok(prefix) = dict.get(p, "prefix")
    Ok(prefix <> name)
  }
  glaml_extended.iteratively_parse_collection(
    root,
    params,
    parse_service,
    "services",
  )
  |> should.equal(Error("services is empty"))
}
