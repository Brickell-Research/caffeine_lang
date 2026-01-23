import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/frontend/ast
import caffeine_lang/frontend/parser
import gleam/set
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
fn string_type() -> accepted_types.AcceptedTypes {
  accepted_types.PrimitiveType(primitive_types.String)
}

fn float_type() -> accepted_types.AcceptedTypes {
  accepted_types.PrimitiveType(primitive_types.NumericType(numeric_types.Float))
}

fn boolean_type() -> accepted_types.AcceptedTypes {
  accepted_types.PrimitiveType(primitive_types.Boolean)
}

fn list_type(
  inner: primitive_types.PrimitiveTypes,
) -> accepted_types.AcceptedTypes {
  accepted_types.CollectionType(
    collection_types.List(accepted_types.PrimitiveType(inner)),
  )
}

fn dict_type(
  key: primitive_types.PrimitiveTypes,
  value: primitive_types.PrimitiveTypes,
) -> accepted_types.AcceptedTypes {
  accepted_types.CollectionType(collection_types.Dict(
    accepted_types.PrimitiveType(key),
    accepted_types.PrimitiveType(value),
  ))
}

fn nested_list_type(
  inner: accepted_types.AcceptedTypes,
) -> accepted_types.AcceptedTypes {
  accepted_types.CollectionType(collection_types.List(inner))
}

fn nested_dict_type(
  key: primitive_types.PrimitiveTypes,
  value: accepted_types.AcceptedTypes,
) -> accepted_types.AcceptedTypes {
  accepted_types.CollectionType(collection_types.Dict(
    accepted_types.PrimitiveType(key),
    value,
  ))
}

fn optional_type(
  inner: accepted_types.AcceptedTypes,
) -> accepted_types.AcceptedTypes {
  accepted_types.ModifierType(modifier_types.Optional(inner))
}

fn defaulted_type(
  inner: accepted_types.AcceptedTypes,
  default: String,
) -> accepted_types.AcceptedTypes {
  accepted_types.ModifierType(modifier_types.Defaulted(inner, default))
}

fn oneof_type(
  base: primitive_types.PrimitiveTypes,
  values: List(String),
) -> accepted_types.AcceptedTypes {
  accepted_types.RefinementType(refinement_types.OneOf(
    accepted_types.PrimitiveType(base),
    set.from_list(values),
  ))
}

fn range_type(
  base: primitive_types.PrimitiveTypes,
  min: String,
  max: String,
) -> accepted_types.AcceptedTypes {
  accepted_types.RefinementType(refinement_types.InclusiveRange(
    accepted_types.PrimitiveType(base),
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
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "api_availability",
              extends: [],
              requires: ast.Struct([
                ast.Field("env", ast.TypeValue(string_type())),
              ]),
              provides: ast.Struct([
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // multiple blocks
    #(
      blueprints_path("happy_path_multiple_blocks"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "availability",
              extends: [],
              requires: ast.Struct([
                ast.Field("env", ast.TypeValue(string_type())),
              ]),
              provides: ast.Struct([
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                ),
              ]),
            ),
          ]),
          ast.BlueprintsBlock(artifacts: ["DependencyRelation"], items: [
            ast.BlueprintItem(
              name: "hard_dep",
              extends: [],
              requires: ast.Struct([
                ast.Field("from", ast.TypeValue(string_type())),
                ast.Field("to", ast.TypeValue(string_type())),
              ]),
              provides: ast.Struct([
                ast.Field("type", ast.LiteralValue(ast.LiteralString("hard"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // multi artifact
    #(
      blueprints_path("happy_path_multi_artifact"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO", "DependencyRelation"], items: [
            ast.BlueprintItem(
              name: "tracked_slo",
              extends: [],
              requires: ast.Struct([
                ast.Field("env", ast.TypeValue(string_type())),
                ast.Field("upstream", ast.TypeValue(string_type())),
              ]),
              provides: ast.Struct([
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                ),
                ast.Field("type", ast.LiteralValue(ast.LiteralString("hard"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // with extendable
    #(
      blueprints_path("happy_path_with_extendable"),
      Ok(
        ast.BlueprintsFile(
          type_aliases: [],
          extendables: [
            ast.Extendable(
              name: "_base",
              kind: ast.ExtendableProvides,
              body: ast.Struct([
                ast.Field(
                  "vendor",
                  ast.LiteralValue(ast.LiteralString("datadog")),
                ),
              ]),
            ),
          ],
          blocks: [
            ast.BlueprintsBlock(artifacts: ["SLO"], items: [
              ast.BlueprintItem(
                name: "api",
                extends: [],
                requires: ast.Struct([
                  ast.Field("env", ast.TypeValue(string_type())),
                ]),
                provides: ast.Struct([
                  ast.Field(
                    "value",
                    ast.LiteralValue(ast.LiteralString("test")),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      ),
    ),
    // with Requires extendable
    #(
      blueprints_path("happy_path_requires_extendable"),
      Ok(
        ast.BlueprintsFile(
          type_aliases: [],
          extendables: [
            ast.Extendable(
              name: "_common",
              kind: ast.ExtendableRequires,
              body: ast.Struct([
                ast.Field("env", ast.TypeValue(string_type())),
                ast.Field("status", ast.TypeValue(boolean_type())),
              ]),
            ),
          ],
          blocks: [
            ast.BlueprintsBlock(artifacts: ["SLO"], items: [
              ast.BlueprintItem(
                name: "api",
                extends: ["_common"],
                requires: ast.Struct([
                  ast.Field("threshold", ast.TypeValue(float_type())),
                ]),
                provides: ast.Struct([
                  ast.Field(
                    "vendor",
                    ast.LiteralValue(ast.LiteralString("datadog")),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      ),
    ),
    // with extends
    #(
      blueprints_path("happy_path_with_extends"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "api",
              extends: ["_base"],
              requires: ast.Struct([
                ast.Field("env", ast.TypeValue(string_type())),
              ]),
              provides: ast.Struct([
                ast.Field("value", ast.LiteralValue(ast.LiteralString("test"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // multiple extends
    #(
      blueprints_path("happy_path_multiple_extends"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "api",
              extends: ["_base", "_common"],
              requires: ast.Struct([
                ast.Field("threshold", ast.TypeValue(float_type())),
              ]),
              provides: ast.Struct([
                ast.Field("value", ast.LiteralValue(ast.LiteralString("test"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
    #(
      blueprints_path("happy_path_advanced_types"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "test",
              extends: [],
              requires: ast.Struct([
                ast.Field(
                  "tags",
                  ast.TypeValue(list_type(primitive_types.String)),
                ),
                ast.Field(
                  "counts",
                  ast.TypeValue(dict_type(
                    primitive_types.String,
                    primitive_types.NumericType(numeric_types.Integer),
                  )),
                ),
                ast.Field("name", ast.TypeValue(optional_type(string_type()))),
                ast.Field(
                  "env",
                  ast.TypeValue(defaulted_type(string_type(), "production")),
                ),
                ast.Field(
                  "status",
                  ast.TypeValue(
                    oneof_type(primitive_types.String, ["active", "inactive"]),
                  ),
                ),
                ast.Field(
                  "threshold",
                  ast.TypeValue(range_type(
                    primitive_types.NumericType(numeric_types.Float),
                    "0.0",
                    "100.0",
                  )),
                ),
              ]),
              provides: ast.Struct([
                ast.Field("value", ast.LiteralValue(ast.LiteralString("x"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // nested collections (List(List), Dict(Dict), Dict(List), List(Dict))
    #(
      blueprints_path("happy_path_nested_collections"),
      Ok(
        ast.BlueprintsFile(type_aliases: [], extendables: [], blocks: [
          ast.BlueprintsBlock(artifacts: ["SLO"], items: [
            ast.BlueprintItem(
              name: "test_nested",
              extends: [],
              requires: ast.Struct([
                // Order must match corpus file
                ast.Field(
                  "nested_list",
                  ast.TypeValue(
                    nested_list_type(
                      nested_list_type(accepted_types.PrimitiveType(
                        primitive_types.String,
                      )),
                    ),
                  ),
                ),
                ast.Field(
                  "nested_dict",
                  ast.TypeValue(nested_dict_type(
                    primitive_types.String,
                    nested_dict_type(
                      primitive_types.String,
                      accepted_types.PrimitiveType(primitive_types.NumericType(
                        numeric_types.Integer,
                      )),
                    ),
                  )),
                ),
                ast.Field(
                  "dict_of_list",
                  ast.TypeValue(nested_dict_type(
                    primitive_types.String,
                    nested_list_type(
                      accepted_types.PrimitiveType(primitive_types.NumericType(
                        numeric_types.Integer,
                      )),
                    ),
                  )),
                ),
                ast.Field(
                  "list_of_dict",
                  ast.TypeValue(
                    nested_list_type(
                      accepted_types.CollectionType(collection_types.Dict(
                        accepted_types.PrimitiveType(primitive_types.String),
                        accepted_types.PrimitiveType(primitive_types.Boolean),
                      )),
                    ),
                  ),
                ),
              ]),
              provides: ast.Struct([
                ast.Field("value", ast.LiteralValue(ast.LiteralString("x"))),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // type alias
    #(
      blueprints_path("happy_path_type_alias"),
      Ok(
        ast.BlueprintsFile(
          type_aliases: [
            ast.TypeAlias(
              name: "_env",
              type_: accepted_types.RefinementType(refinement_types.OneOf(
                accepted_types.PrimitiveType(primitive_types.String),
                set.from_list(["production", "staging", "development"]),
              )),
            ),
          ],
          extendables: [],
          blocks: [
            ast.BlueprintsBlock(artifacts: ["SLO"], items: [
              ast.BlueprintItem(
                name: "test",
                extends: [],
                requires: ast.Struct([
                  ast.Field(
                    "env",
                    ast.TypeValue(accepted_types.TypeAliasRef("_env")),
                  ),
                ]),
                provides: ast.Struct([
                  ast.Field("value", ast.LiteralValue(ast.LiteralString("x"))),
                ]),
              ),
            ]),
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
        ast.ExpectsFile(extendables: [], blocks: [
          ast.ExpectsBlock(blueprint: "api_availability", items: [
            ast.ExpectItem(
              name: "checkout",
              extends: [],
              provides: ast.Struct([
                ast.Field(
                  "env",
                  ast.LiteralValue(ast.LiteralString("production")),
                ),
                ast.Field(
                  "threshold",
                  ast.LiteralValue(ast.LiteralFloat(99.95)),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // multiple blocks
    #(
      expects_path("happy_path_multiple_blocks"),
      Ok(
        ast.ExpectsFile(extendables: [], blocks: [
          ast.ExpectsBlock(blueprint: "api_availability", items: [
            ast.ExpectItem(
              name: "checkout",
              extends: [],
              provides: ast.Struct([
                ast.Field(
                  "threshold",
                  ast.LiteralValue(ast.LiteralFloat(99.95)),
                ),
              ]),
            ),
          ]),
          ast.ExpectsBlock(blueprint: "latency", items: [
            ast.ExpectItem(
              name: "checkout_p99",
              extends: [],
              provides: ast.Struct([
                ast.Field(
                  "threshold_ms",
                  ast.LiteralValue(ast.LiteralInteger(500)),
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
          extendables: [
            ast.Extendable(
              name: "_defaults",
              kind: ast.ExtendableProvides,
              body: ast.Struct([
                ast.Field(
                  "env",
                  ast.LiteralValue(ast.LiteralString("production")),
                ),
                ast.Field(
                  "window_in_days",
                  ast.LiteralValue(ast.LiteralInteger(30)),
                ),
              ]),
            ),
          ],
          blocks: [
            ast.ExpectsBlock(blueprint: "api_availability", items: [
              ast.ExpectItem(
                name: "checkout",
                extends: [],
                provides: ast.Struct([
                  ast.Field(
                    "threshold",
                    ast.LiteralValue(ast.LiteralFloat(99.95)),
                  ),
                ]),
              ),
            ]),
          ],
        ),
      ),
    ),
    // with extends
    #(
      expects_path("happy_path_with_extends"),
      Ok(
        ast.ExpectsFile(extendables: [], blocks: [
          ast.ExpectsBlock(blueprint: "api_availability", items: [
            ast.ExpectItem(
              name: "checkout",
              extends: ["_defaults"],
              provides: ast.Struct([
                ast.Field(
                  "threshold",
                  ast.LiteralValue(ast.LiteralFloat(99.95)),
                ),
                ast.Field("status", ast.LiteralValue(ast.LiteralTrue)),
              ]),
            ),
          ]),
        ]),
      ),
    ),
    // list and struct literals
    #(
      expects_path("happy_path_complex_literals"),
      Ok(
        ast.ExpectsFile(extendables: [], blocks: [
          ast.ExpectsBlock(blueprint: "test", items: [
            ast.ExpectItem(
              name: "item",
              extends: [],
              provides: ast.Struct([
                ast.Field(
                  "tags",
                  ast.LiteralValue(
                    ast.LiteralList([
                      ast.LiteralString("a"),
                      ast.LiteralString("b"),
                    ]),
                  ),
                ),
                ast.Field(
                  "config",
                  ast.LiteralValue(
                    ast.LiteralStruct([
                      ast.Field(
                        "key",
                        ast.LiteralValue(ast.LiteralString("value")),
                      ),
                    ]),
                  ),
                ),
                ast.Field("enabled", ast.LiteralValue(ast.LiteralFalse)),
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
// * ✅ empty file
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
    #(errors_path("empty_file"), True),
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
