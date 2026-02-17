import caffeine_lang/frontend/ast
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/validator
import simplifile
import test_helpers

// ==== Helpers ====
fn validator_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/validator/" <> file_name <> ".caffeine"
}

fn read_file(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

fn parse_blueprints(file_name: String) -> ast.BlueprintsFile {
  let assert Ok(file) =
    validator_path(file_name) |> read_file |> parser.parse_blueprints_file
  file
}

fn parse_expects(file_name: String) -> ast.ExpectsFile {
  let assert Ok(file) =
    validator_path(file_name) |> read_file |> parser.parse_expects_file
  file
}

// ==== validate_blueprints_file ====
// ==== Happy Paths ====
// * ✅ valid - extendables exist, no duplicates
// * ✅ valid - no extendables at all
// * ✅ valid - type aliases with references in Requires
// * ✅ valid - record type with type alias
// ==== Error Cases - Extendables ====
// * ❌ duplicate extendable names
// * ❌ extends references non-existent extendable
// * ❌ multiple items where one references non-existent extendable
// * ❌ duplicate extendable reference in extends list
// ==== Error Cases - Name Collisions ====
// * ❌ extendable name collides with type alias name
// ==== Error Cases - Type Aliases ====
// * ❌ duplicate type alias names
// * ❌ undefined type alias reference
// * ❌ invalid Dict key type alias (non-String)
// ==== Error Cases - Record Type Aliases ====
// * ❌ circular type alias in record field
// * ❌ undefined type alias in record field
pub fn validate_blueprints_file_test() {
  // Happy paths
  [
    #(
      "valid - extendables exist, no duplicates",
      parse_blueprints("blueprints_valid"),
      Ok(Nil),
    ),
    #(
      "valid - no extendables at all",
      parse_blueprints("blueprints_no_extendables"),
      Ok(Nil),
    ),
    #(
      "valid - type aliases with references in Requires",
      parse_blueprints("blueprints_valid_type_alias"),
      Ok(Nil),
    ),
    #(
      "valid - record type with type alias",
      parse_blueprints("blueprints_valid_record_type"),
      Ok(Nil),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    case validator.validate_blueprints_file(file) {
      Ok(_) -> Ok(Nil)
      Error(e) -> Error(e)
    }
  })

  // Duplicate extendable
  [
    #(
      "duplicate extendable names",
      parse_blueprints("blueprints_duplicate_extendable"),
      Error([validator.DuplicateExtendable(name: "_base")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Missing extendable reference
  [
    #(
      "extends references non-existent extendable",
      parse_blueprints("blueprints_missing_extendable"),
      Error([
        validator.UndefinedExtendable(
          name: "_nonexistent",
          referenced_by: "api",
          candidates: ["_base"],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Multiple items, one with missing extendable
  [
    #(
      "multiple items where one references non-existent extendable",
      parse_blueprints("blueprints_multiple_items_one_missing"),
      Error([
        validator.UndefinedExtendable(
          name: "_nonexistent",
          referenced_by: "latency",
          candidates: ["_base"],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Duplicate extendable reference in extends list
  [
    #(
      "duplicate extendable reference in extends list",
      parse_blueprints("blueprints_duplicate_extends_ref"),
      Error([
        validator.DuplicateExtendsReference(name: "_base", referenced_by: "api"),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Extendable name collides with type alias name
  [
    #(
      "extendable name collides with type alias name",
      parse_blueprints("blueprints_extendable_type_alias_collision"),
      Error([validator.ExtendableTypeAliasNameCollision(name: "_env")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Duplicate type alias
  [
    #(
      "duplicate type alias names",
      parse_blueprints("blueprints_duplicate_type_alias"),
      Error([validator.DuplicateTypeAlias(name: "_env")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Undefined type alias reference
  [
    #(
      "undefined type alias reference",
      parse_blueprints("blueprints_undefined_type_alias"),
      Error([
        validator.UndefinedTypeAlias(
          name: "_undefined",
          referenced_by: "test",
          candidates: ["_env"],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Invalid Dict key type alias (non-String type)
  [
    #(
      "invalid Dict key type alias",
      parse_blueprints("blueprints_invalid_dict_key_type_alias"),
      Error([
        validator.InvalidDictKeyTypeAlias(
          alias_name: "_count",
          resolved_to: "Integer { x | x in ( 1..100 ) }",
          referenced_by: "test",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Circular type alias in record field
  [
    #(
      "circular type alias in record field",
      parse_blueprints("blueprints_circular_record_type_alias"),
      Error([validator.CircularTypeAlias(name: "_rec", cycle: ["_rec"])]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })

  // Undefined type alias in record field
  [
    #(
      "undefined type alias in record field",
      parse_blueprints("blueprints_undefined_record_type_alias"),
      Error([
        validator.UndefinedTypeAlias(
          name: "_nope",
          referenced_by: "api",
          candidates: [],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_blueprints_file(file)
  })
}

// ==== validate_expects_file ====
// ==== Happy Paths ====
// * ✅ valid - extendables exist, no duplicates
// * ✅ valid - no extendables at all
// ==== Error Cases ====
// * ❌ duplicate extendable names
// * ❌ extends references non-existent extendable
// * ❌ multiple items where one references non-existent extendable
// * ❌ duplicate extendable reference in extends list
// * ❌ Requires extendable in expects file (only Provides allowed)
pub fn validate_expects_file_test() {
  // Happy paths
  [
    #(
      "valid - extendables exist, no duplicates",
      parse_expects("expects_valid"),
      Ok(Nil),
    ),
    #(
      "valid - no extendables at all",
      parse_expects("expects_no_extendables"),
      Ok(Nil),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    case validator.validate_expects_file(file) {
      Ok(_) -> Ok(Nil)
      Error(e) -> Error(e)
    }
  })

  // Duplicate extendable
  [
    #(
      "duplicate extendable names",
      parse_expects("expects_duplicate_extendable"),
      Error([validator.DuplicateExtendable(name: "_defaults")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })

  // Missing extendable reference
  [
    #(
      "extends references non-existent extendable",
      parse_expects("expects_missing_extendable"),
      Error([
        validator.UndefinedExtendable(
          name: "_nonexistent",
          referenced_by: "checkout",
          candidates: ["_defaults"],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })

  // Multiple items, one with missing extendable
  [
    #(
      "multiple items where one references non-existent extendable",
      parse_expects("expects_multiple_items_one_missing"),
      Error([
        validator.UndefinedExtendable(
          name: "_nonexistent",
          referenced_by: "payment",
          candidates: ["_defaults"],
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })

  // Duplicate extendable reference in extends list
  [
    #(
      "duplicate extendable reference in extends list",
      parse_expects("expects_duplicate_extends_ref"),
      Error([
        validator.DuplicateExtendsReference(
          name: "_defaults",
          referenced_by: "checkout",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })

  // Requires extendable in expects file (invalid per spec)
  [
    #(
      "Requires extendable in expects file",
      parse_expects("expects_requires_extendable"),
      Error([
        validator.InvalidExtendableKind(
          name: "_common",
          expected: "Provides",
          got: "Requires",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })
}
