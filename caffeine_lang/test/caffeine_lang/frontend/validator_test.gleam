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

fn parse_measurements(file_name: String) -> ast.MeasurementsFile(ast.Parsed) {
  let assert Ok(file) =
    validator_path(file_name) |> read_file |> parser.parse_measurements_file
  file
}

fn parse_expects(file_name: String) -> ast.ExpectsFile(ast.Parsed) {
  let assert Ok(file) =
    validator_path(file_name) |> read_file |> parser.parse_expects_file
  file
}

// ==== validate_measurements_file ====
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
// ==== Error Cases - Overshadowing ====
// * ❌ measurement requires field overshadows extendable requires field
// * ❌ measurement provides field overshadows extendable provides field
// * ❌ measurement requires field overshadows one of multiple extended extendables
// ==== Error Cases - Name Collisions ====
// * ❌ extendable name collides with type alias name
// ==== Error Cases - Type Aliases ====
// * ❌ duplicate type alias names
// * ❌ undefined type alias reference
// * ❌ invalid Dict key type alias (non-String)
// ==== Error Cases - Record Type Aliases ====
// * ❌ circular type alias in record field
// * ❌ circular type alias two-level (_a → _b → _a)
// * ❌ circular type alias three-level (_a → _b → _c → _a)
// * ❌ circular type alias through List inner type
// * ❌ undefined type alias in record field
pub fn validate_measurements_file_test() {
  // Happy paths
  [
    #(
      "valid - extendables exist, no duplicates",
      parse_measurements("measurements_valid"),
      Ok(Nil),
    ),
    #(
      "valid - no extendables at all",
      parse_measurements("measurements_no_extendables"),
      Ok(Nil),
    ),
    #(
      "valid - type aliases with references in Requires",
      parse_measurements("measurements_valid_type_alias"),
      Ok(Nil),
    ),
    #(
      "valid - record type with type alias",
      parse_measurements("measurements_valid_record_type"),
      Ok(Nil),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    case validator.validate_measurements_file(file) {
      Ok(_) -> Ok(Nil)
      Error(e) -> Error(e)
    }
  })

  // Duplicate extendable
  [
    #(
      "duplicate extendable names",
      parse_measurements("measurements_duplicate_extendable"),
      Error([validator.DuplicateExtendable(name: "_base")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Missing extendable reference
  [
    #(
      "extends references non-existent extendable",
      parse_measurements("measurements_missing_extendable"),
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
    validator.validate_measurements_file(file)
  })

  // Multiple items, one with missing extendable
  [
    #(
      "multiple items where one references non-existent extendable",
      parse_measurements("measurements_multiple_items_one_missing"),
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
    validator.validate_measurements_file(file)
  })

  // Duplicate extendable reference in extends list
  [
    #(
      "duplicate extendable reference in extends list",
      parse_measurements("measurements_duplicate_extends_ref"),
      Error([
        validator.DuplicateExtendsReference(name: "_base", referenced_by: "api"),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Overshadowing - requires field shadows extendable requires field
  [
    #(
      "measurement requires field overshadows extendable requires field",
      parse_measurements("measurements_overshadow_requires"),
      Error([
        validator.ExtendableOvershadowing(
          field_name: "env",
          item_name: "api",
          extendable_name: "_common",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Overshadowing - provides field shadows extendable provides field
  [
    #(
      "measurement provides field overshadows extendable provides field",
      parse_measurements("measurements_overshadow_provides"),
      Error([
        validator.ExtendableOvershadowing(
          field_name: "vendor",
          item_name: "api",
          extendable_name: "_base",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Overshadowing - requires field shadows one of multiple extended extendables
  [
    #(
      "measurement requires field overshadows one of multiple extended extendables",
      parse_measurements("measurements_overshadow_multiple_extends"),
      Error([
        validator.ExtendableOvershadowing(
          field_name: "threshold",
          item_name: "api",
          extendable_name: "_metrics",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Extendable name collides with type alias name
  [
    #(
      "extendable name collides with type alias name",
      parse_measurements("measurements_extendable_type_alias_collision"),
      Error([validator.ExtendableTypeAliasNameCollision(name: "_env")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Duplicate type alias
  [
    #(
      "duplicate type alias names",
      parse_measurements("measurements_duplicate_type_alias"),
      Error([validator.DuplicateTypeAlias(name: "_env")]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Undefined type alias reference
  [
    #(
      "undefined type alias reference",
      parse_measurements("measurements_undefined_type_alias"),
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
    validator.validate_measurements_file(file)
  })

  // Invalid Dict key type alias (non-String type)
  [
    #(
      "invalid Dict key type alias",
      parse_measurements("measurements_invalid_dict_key_type_alias"),
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
    validator.validate_measurements_file(file)
  })

  // Circular type alias in record field
  [
    #(
      "circular type alias in record field",
      parse_measurements("measurements_circular_record_type_alias"),
      Error([validator.CircularTypeAlias(name: "_rec", cycle: ["_rec"])]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Circular type alias two-level (_a → _b → _a)
  [
    #(
      "circular type alias two-level",
      parse_measurements("measurements_circular_two_level"),
      Error([
        validator.CircularTypeAlias(name: "_a", cycle: ["_b", "_a"]),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Circular type alias three-level (_a → _b → _c → _a)
  [
    #(
      "circular type alias three-level",
      parse_measurements("measurements_circular_three_level"),
      Error([
        validator.CircularTypeAlias(name: "_a", cycle: ["_c", "_b", "_a"]),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Circular type alias through List inner type
  [
    #(
      "circular type alias through List inner type",
      parse_measurements("measurements_circular_through_list"),
      Error([
        validator.CircularTypeAlias(name: "_a", cycle: ["_b", "_a"]),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Undefined type alias in record field
  [
    #(
      "undefined type alias in record field",
      parse_measurements("measurements_undefined_record_type_alias"),
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
    validator.validate_measurements_file(file)
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
// * ❌ expectation provides field overshadows extendable provides field
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

  // Overshadowing - provides field shadows extendable provides field
  [
    #(
      "expectation provides field overshadows extendable provides field",
      parse_expects("expects_overshadow_provides"),
      Error([
        validator.ExtendableOvershadowing(
          field_name: "env",
          item_name: "checkout",
          extendable_name: "_defaults",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_expects_file(file)
  })
}

// ==== Refinement Value Validation ====
// * ❌ refinement type mismatch (e.g. string literal in Integer OneOf)
// * ❌ refinement type mismatch - Float OneOf with string
// * ❌ refinement type mismatch - Boolean OneOf with invalid value
// * ❌ refinement type mismatch - Integer InclusiveRange with string bounds
// * ❌ percentage bounds out of range
pub fn validate_refinement_values_test() {
  // Refinement type mismatch - string "hello" in Integer OneOf
  [
    #(
      "refinement type mismatch",
      parse_measurements("measurements_refinement_type_mismatch"),
      Error([
        validator.InvalidRefinementValue(
          value: "hello",
          expected_type: "Integer",
          referenced_by: "_bad_type",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Refinement type mismatch - Float OneOf with string
  [
    #(
      "refinement type mismatch - Float OneOf with string",
      parse_measurements("measurements_refinement_float_mismatch"),
      Error([
        validator.InvalidRefinementValue(
          value: "hello",
          expected_type: "Float",
          referenced_by: "test",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Refinement type mismatch - Boolean OneOf with invalid value
  [
    #(
      "refinement type mismatch - Boolean OneOf with invalid value",
      parse_measurements("measurements_refinement_bool_mismatch"),
      Error([
        validator.InvalidRefinementValue(
          value: "yes",
          expected_type: "Boolean",
          referenced_by: "test",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Refinement type mismatch - Integer InclusiveRange with string bounds
  [
    #(
      "refinement type mismatch - Integer InclusiveRange with string bounds",
      parse_measurements("measurements_refinement_range_mismatch"),
      Error([
        validator.InvalidRefinementValue(
          value: "a",
          expected_type: "Integer",
          referenced_by: "test",
        ),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })

  // Percentage bounds out of range
  [
    #(
      "percentage bounds out of range",
      parse_measurements("measurements_percentage_bounds"),
      Error([
        validator.InvalidPercentageBounds(value: "200.0", referenced_by: "test"),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(fn(file) {
    validator.validate_measurements_file(file)
  })
}
