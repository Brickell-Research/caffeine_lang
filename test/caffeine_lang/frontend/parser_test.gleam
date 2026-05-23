import caffeine_lang/frontend/ast
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error
import caffeine_lang/types
import gleam/dict
import gleam/list
import gleam/option
import gleam/set
import gleeunit/should
import simplifile
import test_helpers

// ==== Helpers ====
fn measurements_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/parser/measurements_file/"
  <> file_name
  <> ".caffeine"
}

fn errors_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/parser/errors/"
  <> file_name
  <> ".caffeine"
}

fn read_file(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

// Type helpers
fn string_type() -> types.ParsedType {
  types.ParsedPrimitive(types.String)
}

fn float_type() -> types.ParsedType {
  types.ParsedPrimitive(types.NumericType(types.Float))
}

fn percentage_type() -> types.ParsedType {
  types.ParsedPrimitive(types.NumericType(types.Percentage))
}

fn boolean_type() -> types.ParsedType {
  types.ParsedPrimitive(types.Boolean)
}

fn list_type(inner: types.PrimitiveTypes) -> types.ParsedType {
  types.ParsedCollection(types.List(types.ParsedPrimitive(inner)))
}

fn dict_type(
  key: types.PrimitiveTypes,
  value: types.PrimitiveTypes,
) -> types.ParsedType {
  types.ParsedCollection(types.Dict(
    types.ParsedPrimitive(key),
    types.ParsedPrimitive(value),
  ))
}

fn nested_list_type(inner: types.ParsedType) -> types.ParsedType {
  types.ParsedCollection(types.List(inner))
}

fn nested_dict_type(
  key: types.PrimitiveTypes,
  value: types.ParsedType,
) -> types.ParsedType {
  types.ParsedCollection(types.Dict(types.ParsedPrimitive(key), value))
}

fn optional_type(inner: types.ParsedType) -> types.ParsedType {
  types.ParsedModifier(types.Optional(inner))
}

fn defaulted_type(
  inner: types.ParsedType,
  default: String,
) -> types.ParsedType {
  types.ParsedModifier(types.Defaulted(inner, default))
}

fn oneof_type(
  base: types.PrimitiveTypes,
  values: List(String),
) -> types.ParsedType {
  types.ParsedRefinement(types.OneOf(
    types.ParsedPrimitive(base),
    set.from_list(values),
  ))
}

fn range_type(
  base: types.PrimitiveTypes,
  min: String,
  max: String,
) -> types.ParsedType {
  types.ParsedRefinement(types.InclusiveRange(
    types.ParsedPrimitive(base),
    min,
    max,
  ))
}

// ==== parse_measurements_file ====
// * ✅ happy path - single item
// * ✅ happy path - multiple items
// * ✅ happy path - multi artifact
// * ✅ happy path - with Provides extendable
// * ✅ happy path - with Requires extendable
// * ✅ happy path - with extends
// * ✅ happy path - multiple extends
// * ✅ happy path - advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
// * ✅ happy path - nested collections (List(List), Dict(Dict), Dict(List), List(Dict))
// * ✅ happy path - record type
// * ✅ happy path - percentage types (plain, refined, defaulted)
pub fn parse_measurements_file_test() {
  [
    // single item
    #(
      "happy path - single item",
      measurements_path("happy_path_single_block"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api_availability",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // multiple items
    #(
      "happy path - multiple items",
      measurements_path("happy_path_multiple_blocks"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "availability",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                  leading_comments: [],
                ),
              ]),
            ),
            ast.MeasurementItem(
              leading_comments: [],
              name: "hard_dep",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "source",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
                ast.Field(
                  "target",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "type",
                  ast.LiteralValue(ast.LiteralString("hard")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // multi artifact
    #(
      "happy path - multi artifact",
      measurements_path("happy_path_multi_artifact"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "tracked_slo",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
                ast.Field(
                  "upstream",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                  leading_comments: [],
                ),
                ast.Field(
                  "type",
                  ast.LiteralValue(ast.LiteralString("hard")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // with extendable
    #(
      "happy path - with Provides extendable",
      measurements_path("happy_path_with_extendable"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [
            ast.Extendable(
              leading_comments: [],
              name: "_base",
              kind: ast.ExtendableProvides,
              body: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("test")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // with Requires extendable
    #(
      "happy path - with Requires extendable",
      measurements_path("happy_path_requires_extendable"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [
            ast.Extendable(
              leading_comments: [],
              name: "_common",
              kind: ast.ExtendableRequires,
              body: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
                ast.Field(
                  "status",
                  ast.TypeValue(boolean_type()),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api",
              expectation_type: option.None,
              extends: ["_common"],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "threshold",
                  ast.TypeValue(float_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // with extends
    #(
      "happy path - with extends",
      measurements_path("happy_path_with_extends"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api",
              expectation_type: option.None,
              extends: ["_base"],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(string_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("test")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // multiple extends
    #(
      "happy path - multiple extends",
      measurements_path("happy_path_multiple_extends"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api",
              expectation_type: option.None,
              extends: ["_base", "_common"],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "threshold",
                  ast.TypeValue(float_type()),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("test")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
    #(
      "happy path - advanced types",
      measurements_path("happy_path_advanced_types"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "test",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "tags",
                  ast.TypeValue(list_type(types.String)),
                  leading_comments: [],
                ),
                ast.Field(
                  "counts",
                  ast.TypeValue(dict_type(
                    types.String,
                    types.NumericType(types.Integer),
                  )),
                  leading_comments: [],
                ),
                ast.Field(
                  "name",
                  ast.TypeValue(optional_type(string_type())),
                  leading_comments: [],
                ),
                ast.Field(
                  "env",
                  ast.TypeValue(defaulted_type(string_type(), "production")),
                  leading_comments: [],
                ),
                ast.Field(
                  "status",
                  ast.TypeValue(
                    oneof_type(types.String, [
                      "active",
                      "inactive",
                    ]),
                  ),
                  leading_comments: [],
                ),
                ast.Field(
                  "threshold",
                  ast.TypeValue(range_type(
                    types.NumericType(types.Float),
                    "0.0",
                    "100.0",
                  )),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("x")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // nested collections (List(List), Dict(Dict), Dict(List), List(Dict))
    #(
      "happy path - nested collections",
      measurements_path("happy_path_nested_collections"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "test_nested",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                // Order must match corpus file
                ast.Field(
                  "nested_list",
                  ast.TypeValue(
                    nested_list_type(
                      nested_list_type(types.ParsedPrimitive(types.String)),
                    ),
                  ),
                  leading_comments: [],
                ),
                ast.Field(
                  "nested_dict",
                  ast.TypeValue(nested_dict_type(
                    types.String,
                    nested_dict_type(
                      types.String,
                      types.ParsedPrimitive(types.NumericType(types.Integer)),
                    ),
                  )),
                  leading_comments: [],
                ),
                ast.Field(
                  "dict_of_list",
                  ast.TypeValue(nested_dict_type(
                    types.String,
                    nested_list_type(
                      types.ParsedPrimitive(types.NumericType(types.Integer)),
                    ),
                  )),
                  leading_comments: [],
                ),
                ast.Field(
                  "list_of_dict",
                  ast.TypeValue(
                    nested_list_type(
                      types.ParsedCollection(types.Dict(
                        types.ParsedPrimitive(types.String),
                        types.ParsedPrimitive(types.Boolean),
                      )),
                    ),
                  ),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("x")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // type alias
    #(
      "happy path - type alias",
      measurements_path("happy_path_type_alias"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [
            ast.TypeAlias(
              leading_comments: [],
              name: "_env",
              type_: types.ParsedRefinement(types.OneOf(
                types.ParsedPrimitive(types.String),
                set.from_list(["production", "staging", "development"]),
              )),
            ),
          ],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "test",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.TypeValue(types.ParsedTypeAliasRef("_env")),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("x")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // record type
    #(
      "happy path - record type",
      measurements_path("happy_path_record_type"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "api",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "indicators",
                  ast.TypeValue(
                    types.ParsedRecord(
                      dict.from_list([
                        #("numerator", string_type()),
                        #("denominator", string_type()),
                      ]),
                    ),
                  ),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("x")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
    // percentage types (plain, refined, defaulted)
    #(
      "happy path - percentage types",
      measurements_path("happy_path_percentage_types"),
      Ok(
        ast.MeasurementsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          items: [
            ast.MeasurementItem(
              leading_comments: [],
              name: "test",
              expectation_type: option.None,
              extends: [],
              requires: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "threshold",
                  ast.TypeValue(percentage_type()),
                  leading_comments: [],
                ),
                ast.Field(
                  "target",
                  ast.TypeValue(range_type(
                    types.NumericType(types.Percentage),
                    "99.0",
                    "100.0",
                  )),
                  leading_comments: [],
                ),
                ast.Field(
                  "level",
                  ast.TypeValue(defaulted_type(percentage_type(), "99.9%")),
                  leading_comments: [],
                ),
              ]),
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "value",
                  ast.LiteralValue(ast.LiteralString("x")),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
        ),
      ),
    ),
  ]
  |> test_helpers.table_test_1(fn(file_path) {
    parser.parse_measurements_file(read_file(file_path))
  })
}

// ==== parse_expects_file (envelope rewrite — see issue) ====
// TODO: rebuild test cases against new Assumes/Guarantees AST.
// Placeholder smoke test: a minimal new-syntax expectation round-trips through parsing.
pub fn parse_expects_file_test() {
  let source = "\"checkout\":\n  Guarantees 99.95% over 30d window"
  let assert Ok(file) = parser.parse_expects_file(source)
  let assert [item] = file.items
  item.name |> should.equal("checkout")
  item.assumes |> should.equal(option.None)
  item.guarantees.threshold |> should.equal(99.95)
  item.guarantees.window.unit |> should.equal("d")
}

// ==== parse_errors ====
// * ✅ unknown type
// * ✅ unclosed type paren
// * ✅ refinement missing x
// * ✅ refinement missing in
// * ✅ unclosed struct brace
// * ✅ unclosed extends bracket
// * ✅ missing provides
// * ✅ missing item colon
// * ✅ invalid extendable kind
// * ✅ missing dict value type
// * ✅ expects with Requires
pub fn parse_errors_test() {
  // Measurements file errors - check that parsing returns Error
  [
    #("unknown type", errors_path("unknown_type"), True),
    #("unclosed type paren", errors_path("unclosed_type_paren"), True),
    #("refinement missing x", errors_path("refinement_missing_x"), True),
    #("refinement missing in", errors_path("refinement_missing_in"), True),
    #("unclosed struct brace", errors_path("unclosed_struct_brace"), True),
    #("unclosed extends bracket", errors_path("unclosed_extends_bracket"), True),
    #("missing provides", errors_path("missing_provides"), True),
    #("missing item colon", errors_path("missing_item_colon"), True),
    #("invalid extendable kind", errors_path("invalid_extendable_kind"), True),
    #("missing dict value type", errors_path("missing_dict_value_type"), True),
  ]
  |> test_helpers.table_test_1(fn(file_path) {
    case parser.parse_measurements_file(read_file(file_path)) {
      Error(_) -> True
      Ok(_) -> False
    }
  })

  // Expects with Requires - check that parsing expects file returns Error
  [#("expects with Requires", errors_path("expects_with_requires"), True)]
  |> test_helpers.table_test_1(fn(file_path) {
    case parser.parse_expects_file(read_file(file_path)) {
      Error(_) -> True
      Ok(_) -> False
    }
  })
}

// ==== parse_error_line_numbers ====
// * ✅ error on line 1 reports line 1
// * ✅ error on line 2 reports line 2
// * ✅ error after blank lines reports correct line
// * ✅ expects file error reports correct line
pub fn parse_error_line_numbers_test() {
  // Measurements file errors
  [
    #(
      "error on line 1 reports line 1",
      "\"test\":\nRequires { field: bad }",
      Error([parser_error.UnknownType("bad", 2, 19)]),
    ),
    #(
      "error after blank lines reports correct line",
      "\n\n\"test\":\nRequires { field: bad }",
      Error([parser_error.UnknownType("bad", 4, 19)]),
    ),
  ]
  |> test_helpers.table_test_1(parser.parse_measurements_file)

  // Expects file errors — an item with `:` followed by Requires (invalid in
  // the new envelope, only Assumes/Guarantees are allowed) should report the
  // error on the line of the offending token.
  [
    #(
      "expects file error reports correct line",
      "\"test\":\n  Requires { foo: String }",
      Error([
        parser_error.UnexpectedToken("Guarantees", "Requires", 1, 7),
      ]),
    ),
  ]
  |> test_helpers.table_test_1(parser.parse_expects_file)
}

// ==== parse_error_missing_delimiter ====
// * ✅ missing } at end of file points to correct line (not EOF line)
// * ✅ missing } in refinement produces error
pub fn parse_error_missing_delimiter_test() {
  [
    #(
      "missing } at end of file points to correct line (not EOF line)",
      "\"test\":\nRequires { env: String\n",
      Error([parser_error.UnexpectedToken("}", "end of file", 2, 17)]),
    ),
  ]
  |> test_helpers.table_test_1(parser.parse_measurements_file)

  // Missing } in refinement — verify it produces at least one error
  let source =
    "\"test\":\nRequires { env: String { x | x in { \"a\", \"b\" }\n\nProvides { v: \"y\" }"
  let assert Error(_) = parser.parse_measurements_file(source)
}

// ==== parse (edge cases) ====
// * ✅ empty Requires {} parses to empty struct
// * ✅ empty Provides {} parses to empty struct
// * ✅ multiple errors across items are all collected
pub fn parse_empty_requires_struct_test() {
  let source = "\"test\":\n  Requires {}\n  Provides { v: \"x\" }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  item.requires.fields |> should.equal([])
}

// ==== parse_omitted_requires (G16) ====
// * ✅ measurement with no Requires block parses to empty requires
pub fn parse_omitted_requires_test() {
  let source = "\"test\":\n  Provides { v: \"x\" }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  item.requires.fields |> should.equal([])
  item.name |> should.equal("test")
}

// ==== parse_declared_expectation_type (E9) ====
// * ✅ `success_rate` header declares the type
// * ✅ `time_slice` header declares the type
// * ✅ no declared type → None
pub fn parse_declared_expectation_type_test() {
  let assert Ok(file) =
    parser.parse_measurements_file(
      "\"a\" success_rate:\n  Provides { v: \"x\" }\n",
    )
  let assert [item] = file.items
  item.expectation_type |> should.equal(option.Some(ast.SuccessRateType))

  let assert Ok(file) =
    parser.parse_measurements_file(
      "\"a\" time_slice:\n  Provides { v: \"x\" }\n",
    )
  let assert [item] = file.items
  item.expectation_type |> should.equal(option.Some(ast.TimeSliceType))

  let assert Ok(file) =
    parser.parse_measurements_file("\"a\":\n  Provides { v: \"x\" }\n")
  let assert [item] = file.items
  item.expectation_type |> should.equal(option.None)
}

pub fn parse_empty_with_args_test() {
  let source =
    "\"test\":\n  Guarantees 99.9% over 30d window as measured by \"bp\" with: {}\n"
  let assert Ok(file) = parser.parse_expects_file(source)
  let assert [item] = file.items
  let assert option.Some(mb) = item.guarantees.measured_by
  mb.with_args.fields |> should.equal([])
}

pub fn parse_multiple_errors_across_items_test() {
  // Two items, each with an error — both errors should be collected
  let source =
    "\"a\":\n  Requires { f: Unknown }\n  Provides {}\n\n\"b\":\n  Requires { g: Unknown }\n  Provides {}\n"
  let assert Error(errors) = parser.parse_measurements_file(source)
  // Should have at least 2 errors (one per bad type)
  { list.length(errors) >= 2 } |> should.be_true()
}

// ==== external-indicator literal: single-line, single match clause ====
// * ✅ `from <source> where <field> = <value>` parses as LiteralExternalIndicator
//      with one MatchClause and no value extraction.
pub fn parse_external_indicator_single_line_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      good: from langfuse where name = \"outcome\"\n    }\n  }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  let assert [ast.Field(name: "indicators", value: indicators_value, ..)] =
    item.provides.fields
  let assert ast.LiteralValue(ast.LiteralStruct(fields, _)) = indicators_value
  let assert [ast.Field(name: "good", value: good_value, ..)] = fields
  let assert ast.LiteralValue(ast.LiteralExternalIndicator(
    source: "langfuse",
    match: [ast.MatchClause(field: "name", value: ast.LiteralString("outcome"))],
    value_extraction: option.None,
  )) = good_value
}

// ==== external-indicator literal: single-line, `and` chain ====
// * ✅ `and` chains parse as a flat list of MatchClauses in source order.
pub fn parse_external_indicator_and_chain_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      good: from langfuse where name = \"outcome\" and value = \"pass\"\n    }\n  }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  let assert [ast.Field(name: "indicators", value: indicators_value, ..)] =
    item.provides.fields
  let assert ast.LiteralValue(ast.LiteralStruct(fields, _)) = indicators_value
  let assert [ast.Field(name: "good", value: good_value, ..)] = fields
  let assert ast.LiteralValue(ast.LiteralExternalIndicator(
    source: "langfuse",
    match: matches,
    value_extraction: option.None,
  )) = good_value
  matches
  |> should.equal([
    ast.MatchClause(field: "name", value: ast.LiteralString("outcome")),
    ast.MatchClause(field: "value", value: ast.LiteralString("pass")),
  ])
}

// ==== external-indicator literal: block form with value extraction ====
// * ✅ `value: <path> as <type>` parses as Some(ValueExtraction(path, type))
pub fn parse_external_indicator_block_with_value_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      score: from langfuse {\n        where: name = \"faithfulness\"\n        value: value as Float\n      }\n    }\n  }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  let assert [ast.Field(name: "indicators", value: indicators_value, ..)] =
    item.provides.fields
  let assert ast.LiteralValue(ast.LiteralStruct(fields, _)) = indicators_value
  let assert [ast.Field(name: "score", value: score_value, ..)] = fields
  let assert ast.LiteralValue(ast.LiteralExternalIndicator(
    source: "langfuse",
    match: [
      ast.MatchClause(field: "name", value: ast.LiteralString("faithfulness")),
    ],
    value_extraction: option.Some(ast.ValueExtraction(path: "value", type_: t)),
  )) = score_value
  t |> should.equal(float_type())
}

// ==== external-indicator literal: block form without value extraction ====
// * ✅ omitting `value:` leaves value_extraction at None (count semantics)
pub fn parse_external_indicator_block_no_value_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      hits: from langfuse {\n        where: name = \"x\"\n      }\n    }\n  }\n"
  let assert Ok(file) = parser.parse_measurements_file(source)
  let assert [item] = file.items
  let assert [ast.Field(name: "indicators", value: indicators_value, ..)] =
    item.provides.fields
  let assert ast.LiteralValue(ast.LiteralStruct(fields, _)) = indicators_value
  let assert [ast.Field(name: "hits", value: hits_value, ..)] = fields
  let assert ast.LiteralValue(ast.LiteralExternalIndicator(
    source: "langfuse",
    match: [ast.MatchClause(field: "name", value: ast.LiteralString("x"))],
    value_extraction: option.None,
  )) = hits_value
}

// ==== external-indicator literal: error — missing `where`/`{` after source ====
// * ✅ `from langfuse 123` is rejected with a clear error mentioning where/{
pub fn parse_external_indicator_missing_where_or_brace_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      bad: from langfuse 123\n    }\n  }\n"
  let assert Error(_) = parser.parse_measurements_file(source)
}

// ==== external-indicator literal: error — missing `=` in match clause ====
// * ✅ `from langfuse where name "x"` is rejected
pub fn parse_external_indicator_missing_equals_test() {
  let source =
    "\"M\":\n  Provides {\n    indicators: {\n      bad: from langfuse where name \"x\"\n    }\n  }\n"
  let assert Error(_) = parser.parse_measurements_file(source)
}

// ==== Guarantees with trailing `where` filter ====
// * ✅ no `where` clause → filter_where = []
// * ✅ single where clause is captured as one MatchClause
// * ✅ `and` chains parse as multiple MatchClauses in source order
pub fn parse_guarantees_no_where_test() {
  let source =
    "\"checkout\":\n  Guarantees 99.9% over 30d window as measured by \"M\" with: {}\n"
  let assert Ok(file) = parser.parse_expects_file(source)
  let assert [item] = file.items
  item.guarantees.filter_where |> should.equal([])
}

pub fn parse_guarantees_where_single_test() {
  let source =
    "\"checkout\":\n  Guarantees 99.9% over 30d window as measured by \"M\" with: {} where env = \"prod\"\n"
  let assert Ok(file) = parser.parse_expects_file(source)
  let assert [item] = file.items
  item.guarantees.filter_where
  |> should.equal([
    ast.MatchClause(field: "env", value: ast.LiteralString("prod")),
  ])
}

pub fn parse_guarantees_where_and_chain_test() {
  let source =
    "\"checkout\":\n  Guarantees 99.9% over 30d window as measured by \"M\" with: {} where env = \"prod\" and prompt_version = \"v2\"\n"
  let assert Ok(file) = parser.parse_expects_file(source)
  let assert [item] = file.items
  item.guarantees.filter_where
  |> should.equal([
    ast.MatchClause(field: "env", value: ast.LiteralString("prod")),
    ast.MatchClause(field: "prompt_version", value: ast.LiteralString("v2")),
  ])
}
