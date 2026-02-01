import caffeine_lang/common/types
import caffeine_lang/frontend/ast
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/parser_error
import gleam/set
import gleeunit/should
import simplifile
import test_helpers

// ==== Helpers ====
fn blueprints_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/parser/blueprints_file/"
  <> file_name
  <> ".caffeine"
}

fn expects_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/parser/expects_file/"
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

fn defaulted_type(inner: types.ParsedType, default: String) -> types.ParsedType {
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

// ==== parse_blueprints_file ====
// * ✅ happy path - single block
// * ✅ happy path - multiple blocks
// * ✅ happy path - multi artifact
// * ✅ happy path - with Provides extendable
// * ✅ happy path - with Requires extendable
// * ✅ happy path - with extends
// * ✅ happy path - multiple extends
// * ✅ happy path - advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
// * ✅ happy path - nested collections (List(List), Dict(Dict), Dict(List), List(Dict))
pub fn parse_blueprints_file_test() {
  [
    // single block
    #(
      blueprints_path("happy_path_single_block"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "api_availability",
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
          ],
        ),
      ),
    ),
    // multiple blocks
    #(
      blueprints_path("happy_path_multiple_blocks"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "availability",
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
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["DependencyRelation"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "hard_dep",
                  extends: [],
                  requires: ast.Struct(trailing_comments: [], fields: [
                    ast.Field(
                      "from",
                      ast.TypeValue(string_type()),
                      leading_comments: [],
                    ),
                    ast.Field(
                      "to",
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
          ],
        ),
      ),
    ),
    // multi artifact
    #(
      blueprints_path("happy_path_multi_artifact"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO", "DependencyRelation"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "tracked_slo",
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
          ],
        ),
      ),
    ),
    // with extendable
    #(
      blueprints_path("happy_path_with_extendable"),
      Ok(
        ast.BlueprintsFile(
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
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "api",
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
          ],
        ),
      ),
    ),
    // with Requires extendable
    #(
      blueprints_path("happy_path_requires_extendable"),
      Ok(
        ast.BlueprintsFile(
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
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "api",
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
          ],
        ),
      ),
    ),
    // with extends
    #(
      blueprints_path("happy_path_with_extends"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "api",
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
          ],
        ),
      ),
    ),
    // multiple extends
    #(
      blueprints_path("happy_path_multiple_extends"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "api",
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
          ],
        ),
      ),
    ),
    // advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
    #(
      blueprints_path("happy_path_advanced_types"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "test",
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
          ],
        ),
      ),
    ),
    // nested collections (List(List), Dict(Dict), Dict(List), List(Dict))
    #(
      blueprints_path("happy_path_nested_collections"),
      Ok(
        ast.BlueprintsFile(
          trailing_comments: [],
          type_aliases: [],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "test_nested",
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
          ],
        ),
      ),
    ),
    // type alias
    #(
      blueprints_path("happy_path_type_alias"),
      Ok(
        ast.BlueprintsFile(
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
          blocks: [
            ast.BlueprintsBlock(
              leading_comments: [],
              artifacts: ["SLO"],
              items: [
                ast.BlueprintItem(
                  leading_comments: [],
                  name: "test",
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
          ],
        ),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parser.parse_blueprints_file(read_file(file_path))
  })
}

// ==== parse_expects_file ====
// * ✅ happy path - single block
// * ✅ happy path - multiple blocks
// * ✅ happy path - with extendable
// * ✅ happy path - with extends
// * ✅ happy path - list and struct literals
pub fn parse_expects_file_test() {
  [
    // single block
    #(
      expects_path("happy_path_single_block"),
      Ok(
        ast.ExpectsFile(trailing_comments: [], extendables: [], blocks: [
          ast.ExpectsBlock(
            leading_comments: [],
            blueprint: "api_availability",
            items: [
              ast.ExpectItem(
                leading_comments: [],
                name: "checkout",
                extends: [],
                provides: ast.Struct(trailing_comments: [], fields: [
                  ast.Field(
                    "env",
                    ast.LiteralValue(ast.LiteralString("production")),
                    leading_comments: [],
                  ),
                  ast.Field(
                    "threshold",
                    ast.LiteralValue(ast.LiteralFloat(99.95)),
                    leading_comments: [],
                  ),
                ]),
              ),
            ],
          ),
        ]),
      ),
    ),
    // multiple blocks
    #(
      expects_path("happy_path_multiple_blocks"),
      Ok(
        ast.ExpectsFile(trailing_comments: [], extendables: [], blocks: [
          ast.ExpectsBlock(
            leading_comments: [],
            blueprint: "api_availability",
            items: [
              ast.ExpectItem(
                leading_comments: [],
                name: "checkout",
                extends: [],
                provides: ast.Struct(trailing_comments: [], fields: [
                  ast.Field(
                    "threshold",
                    ast.LiteralValue(ast.LiteralFloat(99.95)),
                    leading_comments: [],
                  ),
                ]),
              ),
            ],
          ),
          ast.ExpectsBlock(leading_comments: [], blueprint: "latency", items: [
            ast.ExpectItem(
              leading_comments: [],
              name: "checkout_p99",
              extends: [],
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "threshold_ms",
                  ast.LiteralValue(ast.LiteralInteger(500)),
                  leading_comments: [],
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // with extendable
    #(
      expects_path("happy_path_with_extendable"),
      Ok(
        ast.ExpectsFile(
          trailing_comments: [],
          extendables: [
            ast.Extendable(
              leading_comments: [],
              name: "_defaults",
              kind: ast.ExtendableProvides,
              body: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "env",
                  ast.LiteralValue(ast.LiteralString("production")),
                  leading_comments: [],
                ),
                ast.Field(
                  "window_in_days",
                  ast.LiteralValue(ast.LiteralInteger(30)),
                  leading_comments: [],
                ),
              ]),
            ),
          ],
          blocks: [
            ast.ExpectsBlock(
              leading_comments: [],
              blueprint: "api_availability",
              items: [
                ast.ExpectItem(
                  leading_comments: [],
                  name: "checkout",
                  extends: [],
                  provides: ast.Struct(trailing_comments: [], fields: [
                    ast.Field(
                      "threshold",
                      ast.LiteralValue(ast.LiteralFloat(99.95)),
                      leading_comments: [],
                    ),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    // with extends
    #(
      expects_path("happy_path_with_extends"),
      Ok(
        ast.ExpectsFile(trailing_comments: [], extendables: [], blocks: [
          ast.ExpectsBlock(
            leading_comments: [],
            blueprint: "api_availability",
            items: [
              ast.ExpectItem(
                leading_comments: [],
                name: "checkout",
                extends: ["_defaults"],
                provides: ast.Struct(trailing_comments: [], fields: [
                  ast.Field(
                    "threshold",
                    ast.LiteralValue(ast.LiteralFloat(99.95)),
                    leading_comments: [],
                  ),
                  ast.Field(
                    "status",
                    ast.LiteralValue(ast.LiteralTrue),
                    leading_comments: [],
                  ),
                ]),
              ),
            ],
          ),
        ]),
      ),
    ),
    // list and struct literals
    #(
      expects_path("happy_path_complex_literals"),
      Ok(
        ast.ExpectsFile(trailing_comments: [], extendables: [], blocks: [
          ast.ExpectsBlock(leading_comments: [], blueprint: "test", items: [
            ast.ExpectItem(
              leading_comments: [],
              name: "item",
              extends: [],
              provides: ast.Struct(trailing_comments: [], fields: [
                ast.Field(
                  "tags",
                  ast.LiteralValue(
                    ast.LiteralList([
                      ast.LiteralString("a"),
                      ast.LiteralString("b"),
                    ]),
                  ),
                  leading_comments: [],
                ),
                ast.Field(
                  "config",
                  ast.LiteralValue(
                    ast.LiteralStruct([
                      ast.Field(
                        "key",
                        ast.LiteralValue(ast.LiteralString("value")),
                        leading_comments: [],
                      ),
                    ]),
                  ),
                  leading_comments: [],
                ),
                ast.Field(
                  "enabled",
                  ast.LiteralValue(ast.LiteralFalse),
                  leading_comments: [],
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    parser.parse_expects_file(read_file(file_path))
  })
}

// ==== parse_errors ====
// * ✅ missing Blueprints keyword
// * ✅ missing for keyword
// * ✅ missing artifact name
// * ✅ missing blueprint name
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
// * ✅ refinement type mismatch (e.g. Integer in String OneOf)
// * ✅ expects with Requires
pub fn parse_errors_test() {
  // Blueprints file errors - check that parsing returns Error
  [
    #(errors_path("missing_blueprints_keyword"), True),
    #(errors_path("missing_for_keyword"), True),
    #(errors_path("missing_artifact_name"), True),
    #(errors_path("missing_blueprint_name"), True),
    #(errors_path("unknown_type"), True),
    #(errors_path("unclosed_type_paren"), True),
    #(errors_path("refinement_missing_x"), True),
    #(errors_path("refinement_missing_in"), True),
    #(errors_path("unclosed_struct_brace"), True),
    #(errors_path("unclosed_extends_bracket"), True),
    #(errors_path("missing_provides"), True),
    #(errors_path("missing_item_colon"), True),
    #(errors_path("invalid_extendable_kind"), True),
    #(errors_path("missing_dict_value_type"), True),
    #(errors_path("refinement_type_mismatch"), True),
  ]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    case parser.parse_blueprints_file(read_file(file_path)) {
      Error(_) -> True
      Ok(_) -> False
    }
  })

  // Expects with Requires - check that parsing expects file returns Error
  [#(errors_path("expects_with_requires"), True)]
  |> test_helpers.array_based_test_executor_1(fn(file_path) {
    case parser.parse_expects_file(read_file(file_path)) {
      Error(_) -> True
      Ok(_) -> False
    }
  })
}

// ==== parse_error_line_numbers ====
// * ✅ error on line 1 reports line 1
// * ✅ error on line 2 reports line 2
// * ✅ error on line 3 reports line 3
// * ✅ error after blank lines reports correct line
// * ✅ expects file error reports correct line
pub fn parse_error_line_numbers_test() {
  // Error on line 1: first token is wrong
  parser.parse_blueprints_file("\"SLO\"")
  |> should.equal(
    Error(parser_error.UnexpectedToken("Blueprints", "\"SLO\"", 1, 1)),
  )

  // Error on line 2: unexpected token after valid first line
  parser.parse_blueprints_file("Blueprints for \"SLO\"\ninvalid")
  |> should.equal(
    Error(parser_error.UnexpectedToken("Blueprints", "invalid", 2, 1)),
  )

  // Error on line 3: unknown type
  parser.parse_blueprints_file(
    "Blueprints for \"SLO\"\n* \"test\":\nRequires { field: bad }",
  )
  |> should.equal(Error(parser_error.UnknownType("bad", 3, 19)))

  // Error after blank lines: blank lines are counted
  parser.parse_blueprints_file(
    "Blueprints for \"SLO\"\n\n\n* \"test\":\nRequires { field: bad }",
  )
  |> should.equal(Error(parser_error.UnknownType("bad", 5, 19)))

  // Expects file: error on line 2
  parser.parse_expects_file("Expectations for \"test\"\ninvalid")
  |> should.equal(
    Error(parser_error.UnexpectedToken("Expectations", "invalid", 2, 1)),
  )
}

// ==== parse_error_missing_delimiter ====
// * ✅ missing } at end of file points to correct line (not EOF line)
// * ✅ missing } in middle of file points to correct line (not far-away next token)
// * ✅ missing } in refinement points to last token on same line
pub fn parse_error_missing_delimiter_test() {
  // Missing } at end of file with trailing newline:
  // Error should point to line 3 (where } belongs), not line 4 (EOF)
  parser.parse_blueprints_file(
    "Blueprints for \"SLO\"\n* \"test\":\nRequires { env: String\n",
  )
  |> should.equal(
    Error(parser_error.UnexpectedToken("}", "end of file", 3, 17)),
  )

  // Missing } in middle of file:
  // Error should point to line 3 (last consumed token), not line 6 (next Blueprints keyword)
  parser.parse_blueprints_file(
    "Blueprints for \"SLO\"\n* \"test\":\nRequires { env: String\n\n\nBlueprints for \"Other\"",
  )
  |> should.equal(Error(parser_error.UnexpectedToken("}", "Blueprints", 3, 17)))

  // Missing outer } in refinement:
  // Error should point to line 1 (position of inner }), not wherever next token is
  parser.parse_blueprints_file(
    "Blueprints for \"SLO\"\n* \"test\":\nRequires { env: String { x | x in { \"a\", \"b\" }\n\nProvides { v: \"y\" }",
  )
  |> should.equal(Error(parser_error.UnexpectedToken("}", "Provides", 3, 46)))
}
