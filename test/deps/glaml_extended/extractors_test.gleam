import deps/glaml_extended/extractors
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import deps/glaml_extended/yaml
import gleam/dict

fn yaml_to_root(yaml_str: String) -> yaml.Node {
  let assert Ok([doc]) = yaml.parse_string(yaml_str)
  yaml.document_root(doc)
}

pub fn extractors_test() {
  describe("extractors", fn() {
    describe("extract_string_from_node", fn() {
      let root = yaml_to_root("name: test_value")

      it("should extract a string from a node", fn() {
        extractors.extract_string_from_node(root, "name")
        |> gleeunit.equal(Ok("test_value"))
      })

      it("should return an error if the node is missing", fn() {
        extractors.extract_string_from_node(root, "missing")
        |> gleeunit.be_error()
      })
    })

    describe("extract_int_from_node", fn() {
      let root = yaml_to_root("count: 42")

      it("should extract an integer from a node", fn() {
        extractors.extract_int_from_node(root, "count")
        |> gleeunit.equal(Ok(42))
      })

      it("should return an error if the node is missing", fn() {
        extractors.extract_int_from_node(root, "missing")
        |> gleeunit.be_error()
      })
    })

    describe("extract_float_from_node", fn() {
      let root = yaml_to_root("threshold: 99.9")

      it("should extract a float from a node", fn() {
        extractors.extract_float_from_node(root, "threshold")
        |> gleeunit.equal(Ok(99.9))
      })

      it("should return an error if the node is missing", fn() {
        extractors.extract_float_from_node(root, "missing")
        |> gleeunit.be_error()
      })
    })

    describe("extract_bool_from_node", fn() {
      let root = yaml_to_root("enabled: true")

      it("should extract a boolean from a node", fn() {
        extractors.extract_bool_from_node(root, "enabled")
        |> gleeunit.equal(Ok(True))
      })

      it("should return an error if the node is missing", fn() {
        extractors.extract_bool_from_node(root, "missing")
        |> gleeunit.be_error()
      })
    })

    describe("extract_string_list_from_node", fn() {
      let root = yaml_to_root("items:\n  - first\n  - second")

      it("should extract a list of strings from a node", fn() {
        extractors.extract_string_list_from_node(root, "items")
        |> gleeunit.equal(Ok(["first", "second"]))
      })

      it("should return an error if the node is missing", fn() {
        extractors.extract_string_list_from_node(root, "missing")
        |> gleeunit.be_error()
      })
    })

    describe("extract_dict_strings_from_node", fn() {
      let root = yaml_to_root("labels:\n  env: production\n  team: platform")
      let result = extractors.extract_dict_strings_from_node(root, "labels")
      let assert Ok(dict_result) = result

      it(
        "should extract a dictionary values of a string value from a node",
        fn() {
          dict.get(dict_result, "env")
          |> gleeunit.equal(Ok("production"))
        },
      )

      it("should return an empty dict if the node is missing", fn() {
        extractors.extract_dict_strings_from_node(root, "missing")
        |> gleeunit.equal(Ok(dict.new()))
      })
    })

    describe("iteratively_parse_collection", fn() {
      let root =
        yaml_to_root("services:\n  - name: service1\n  - name: service2")
      let parse_service = fn(node, _params) {
        extractors.extract_string_from_node(node, "name")
      }

      it(
        "should parse a collection of nodes and return a list of strings",
        fn() {
          extractors.iteratively_parse_collection(
            root,
            dict.new(),
            parse_service,
            "services",
          )
          |> gleeunit.equal(Ok(["service1", "service2"]))
        },
      )

      it("should return an error if the node is missing", fn() {
        extractors.iteratively_parse_collection(
          root,
          dict.new(),
          parse_service,
          "missing",
        )
        |> gleeunit.be_error()
      })
    })
  })
}
