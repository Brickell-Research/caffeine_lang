import deps/glaml_extended/yaml
import deps/gleamy_spec/extensions.{describe, it}
import deps/gleamy_spec/gleeunit
import gleam/result

pub fn yaml_test() {
  describe("yaml", fn() {
    describe("parse_string", fn() {
      it("should parse a simple YAML string", fn() {
        yaml.parse_string("name: test")
        |> result.map(fn(docs) {
          case docs {
            [_] -> True
            _ -> False
          }
        })
        |> gleeunit.equal(Ok(True))
      })

      it("should parse multiple YAML documents", fn() {
        yaml.parse_string("---\nname: first\n---\nname: second")
        |> result.map(fn(docs) {
          case docs {
            [_, _] -> True
            _ -> False
          }
        })
        |> gleeunit.equal(Ok(True))
      })

      it("should return error for invalid YAML", fn() {
        yaml.parse_string("invalid: yaml: syntax: :")
        |> gleeunit.be_error()
      })
    })

    describe("document_root", fn() {
      it("should extract root node from document", fn() {
        let assert Ok([doc]) = yaml.parse_string("key: value")
        let root = yaml.document_root(doc)
        case root {
          yaml.NodeMap(_) -> True
          _ -> False
        }
        |> gleeunit.equal(True)
      })

      it("should handle list as root", fn() {
        let assert Ok([doc]) = yaml.parse_string("- item1\n- item2")
        let root = yaml.document_root(doc)
        case root {
          yaml.NodeSeq(_) -> True
          _ -> False
        }
        |> gleeunit.equal(True)
      })

      it("should handle scalar as root", fn() {
        let assert Ok([doc]) = yaml.parse_string("just a string")
        let root = yaml.document_root(doc)
        case root {
          yaml.NodeStr(_) -> True
          _ -> False
        }
        |> gleeunit.equal(True)
      })
    })

    describe("select_sugar", fn() {
      it("should select a key from a map", fn() {
        let assert Ok([doc]) = yaml.parse_string("name: test_value")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "name")
        |> gleeunit.equal(Ok(yaml.NodeStr("test_value")))
      })

      it("should select nested keys", fn() {
        let assert Ok([doc]) =
          yaml.parse_string("outer:\n  inner: nested_value")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "outer.inner")
        |> gleeunit.equal(Ok(yaml.NodeStr("nested_value")))
      })

      it("should select item from list by index", fn() {
        let assert Ok([doc]) =
          yaml.parse_string("items:\n  - first\n  - second")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "items.#1")
        |> gleeunit.equal(Ok(yaml.NodeStr("second")))
      })

      it("should return error for missing key", fn() {
        let assert Ok([doc]) = yaml.parse_string("name: test")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "missing")
        |> gleeunit.be_error()
      })

      it("should return error for out of bounds index", fn() {
        let assert Ok([doc]) = yaml.parse_string("items:\n  - first")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "items.#5")
        |> gleeunit.be_error()
      })

      it("should handle empty path", fn() {
        let assert Ok([doc]) = yaml.parse_string("name: test")
        let root = yaml.document_root(doc)
        case yaml.select_sugar(root, "") {
          Ok(yaml.NodeMap(_)) -> True
          _ -> False
        }
        |> gleeunit.equal(True)
      })

      it("should error on empty for non-collections", fn() {
        let assert Ok([doc]) = yaml.parse_string("name:")
        let root = yaml.document_root(doc)
        case yaml.select_sugar(root, "") {
          Ok(yaml.NodeMap(_)) -> True
          _ -> False
        }
        |> gleeunit.equal(True)
      })
    })

    describe("node types", fn() {
      it("should parse integers", fn() {
        let assert Ok([doc]) = yaml.parse_string("count: 42")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "count")
        |> gleeunit.equal(Ok(yaml.NodeInt(42)))
      })

      it("should parse floats", fn() {
        let assert Ok([doc]) = yaml.parse_string("value: 3.14")
        let root = yaml.document_root(doc)
        case yaml.select_sugar(root, "value") {
          Ok(yaml.NodeFloat(f)) -> f >. 3.13 && f <. 3.15
          _ -> False
        }
        |> gleeunit.equal(True)
      })

      it("should parse booleans", fn() {
        let assert Ok([doc]) = yaml.parse_string("enabled: true")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "enabled")
        |> gleeunit.equal(Ok(yaml.NodeBool(True)))
      })

      it("should parse null", fn() {
        let assert Ok([doc]) = yaml.parse_string("empty: null")
        let root = yaml.document_root(doc)
        yaml.select_sugar(root, "empty")
        |> gleeunit.equal(Ok(yaml.NodeNull))
      })
    })
  })
}
