import glaml
import glaml_extended/extractors
import gleam/dict
import gleeunit/should

pub fn extract_string_from_node_test() {
  let yaml = "name: test_value"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  extractors.extract_string_from_node(root, "name")
  |> should.equal(Ok("test_value"))

  extractors.extract_string_from_node(root, "missing")
  |> should.be_error()
}

pub fn extract_int_from_node_test() {
  let yaml = "count: 42"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  extractors.extract_int_from_node(root, "count")
  |> should.equal(Ok(42))

  extractors.extract_int_from_node(root, "missing")
  |> should.be_error()
}

pub fn extract_float_from_node_test() {
  let yaml = "threshold: 99.9"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  extractors.extract_float_from_node(root, "threshold")
  |> should.equal(Ok(99.9))

  extractors.extract_float_from_node(root, "missing")
  |> should.be_error()
}

pub fn extract_bool_from_node_test() {
  let yaml = "enabled: true"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  extractors.extract_bool_from_node(root, "enabled")
  |> should.equal(Ok(True))

  extractors.extract_bool_from_node(root, "missing")
  |> should.be_error()
}

pub fn extract_string_list_from_node_test() {
  let yaml = "items:\n  - first\n  - second"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  extractors.extract_string_list_from_node(root, "items")
  |> should.equal(Ok(["first", "second"]))

  extractors.extract_string_list_from_node(root, "missing")
  |> should.be_error()
}

pub fn extract_dict_strings_from_node_test() {
  let yaml = "labels:\n  env: production\n  team: platform"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  let result = extractors.extract_dict_strings_from_node(root, "labels")
  let assert Ok(dict_result) = result

  dict.get(dict_result, "env")
  |> should.equal(Ok("production"))

  dict.get(dict_result, "team")
  |> should.equal(Ok("platform"))

  // Missing key should return empty dict
  extractors.extract_dict_strings_from_node(root, "missing")
  |> should.equal(Ok(dict.new()))
}

pub fn iteratively_parse_collection_test() {
  let yaml = "services:\n  - name: service1\n  - name: service2"
  let assert Ok([doc]) = glaml.parse_string(yaml)
  let root = glaml.document_root(doc)

  let parse_service = fn(node, _params) {
    extractors.extract_string_from_node(node, "name")
  }

  extractors.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "services",
  )
  |> should.equal(Ok(["service1", "service2"]))

  extractors.iteratively_parse_collection(
    root,
    dict.new(),
    parse_service,
    "missing",
  )
  |> should.be_error()
}
