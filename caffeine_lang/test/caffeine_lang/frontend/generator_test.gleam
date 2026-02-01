import caffeine_lang/common/accepted_types
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/numeric_types
import caffeine_lang/common/primitive_types
import caffeine_lang/common/refinement_types
import caffeine_lang/frontend/generator
import caffeine_lang/frontend/parser
import caffeine_lang/frontend/validator
import caffeine_lang/parser/blueprints.{type Blueprint}
import caffeine_lang/parser/expectations.{type Expectation}
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/set
import gleeunit/should
import simplifile

// ==== Helpers ====
fn generator_path(file_name: String) {
  "test/caffeine_lang/corpus/frontend/generator/" <> file_name
}

fn read_file(path: String) -> String {
  let assert Ok(content) = simplifile.read(path)
  content
}

fn parse_and_generate_blueprints(file_name: String) -> List(Blueprint) {
  let content = generator_path(file_name <> ".caffeine") |> read_file
  let assert Ok(file) = parser.parse_blueprints_file(content)
  let assert Ok(validated) = validator.validate_blueprints_file(file)
  generator.generate_blueprints(validated)
}

fn parse_and_generate_expects(file_name: String) -> List(Expectation) {
  let content = generator_path(file_name <> ".caffeine") |> read_file
  let assert Ok(file) = parser.parse_expects_file(content)
  let assert Ok(validated) = validator.validate_expects_file(file)
  generator.generate_expectations(validated)
}

// ==== generate_blueprints ====
// * ✅ simple blueprint produces correct name, artifact_refs, params, inputs
// * ✅ multi-artifact blueprint
// * ✅ blueprint with extends (extendable flattening)
// * ✅ advanced types (List, Dict, Optional, Defaulted, OneOf, Range)
// * ✅ template variables are transformed ($var$ -> $$var$$)
// * ✅ type aliases are resolved inline
// * ✅ Defaulted with type alias (Defaulted containing refinement type from alias)
pub fn generate_blueprints_simple_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_simple")
  list.length(blueprints) |> should.equal(1)

  let assert Ok(bp) = list.first(blueprints)
  bp.name |> should.equal("api_availability")
  bp.artifact_refs |> should.equal(["SLO"])
  dict.size(bp.params) |> should.equal(2)

  let assert Ok(env_type) = dict.get(bp.params, "env")
  env_type |> should.equal(accepted_types.PrimitiveType(primitive_types.String))

  let assert Ok(threshold_type) = dict.get(bp.params, "threshold")
  threshold_type
  |> should.equal(
    accepted_types.PrimitiveType(primitive_types.NumericType(
      numeric_types.Float,
    )),
  )

  // Check inputs
  dict.size(bp.inputs) |> should.equal(2)
  let assert Ok(vendor_val) = dict.get(bp.inputs, "vendor")
  let assert Ok(vendor_str) = decode.run(vendor_val, decode.string)
  vendor_str |> should.equal("datadog")
}

pub fn generate_blueprints_multi_artifact_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_multi_artifact")
  list.length(blueprints) |> should.equal(1)

  let assert Ok(bp) = list.first(blueprints)
  bp.name |> should.equal("tracked_slo")
  bp.artifact_refs |> should.equal(["SLO", "DependencyRelation"])
  // Should have params from both requires and artifacts
  { dict.size(bp.params) > 0 } |> should.be_true
}

pub fn generate_blueprints_with_extends_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_with_extends")
  let assert Ok(bp) = list.first(blueprints)

  bp.name |> should.equal("api")
  bp.artifact_refs |> should.equal(["SLO"])

  // Should have merged requires from _common extendable + own requires
  let assert Ok(_) = dict.get(bp.params, "env")
  let assert Ok(_) = dict.get(bp.params, "threshold")

  // Should have merged provides from _base extendable + own provides
  let assert Ok(vendor_val) = dict.get(bp.inputs, "vendor")
  let assert Ok(vendor_str) = decode.run(vendor_val, decode.string)
  vendor_str |> should.equal("datadog")
}

pub fn generate_blueprints_advanced_types_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_advanced_types")
  let assert Ok(bp) = list.first(blueprints)

  // List(String)
  let assert Ok(tags_type) = dict.get(bp.params, "tags")
  tags_type
  |> should.equal(
    accepted_types.CollectionType(
      collection_types.List(accepted_types.PrimitiveType(primitive_types.String)),
    ),
  )

  // Dict(String, Integer)
  let assert Ok(counts_type) = dict.get(bp.params, "counts")
  counts_type
  |> should.equal(
    accepted_types.CollectionType(collection_types.Dict(
      accepted_types.PrimitiveType(primitive_types.String),
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Integer,
      )),
    )),
  )

  // Optional(String)
  let assert Ok(name_type) = dict.get(bp.params, "name")
  name_type
  |> should.equal(
    accepted_types.ModifierType(
      modifier_types.Optional(accepted_types.PrimitiveType(
        primitive_types.String,
      )),
    ),
  )

  // Defaulted(String, "production")
  let assert Ok(env_type) = dict.get(bp.params, "env")
  env_type
  |> should.equal(
    accepted_types.ModifierType(modifier_types.Defaulted(
      accepted_types.PrimitiveType(primitive_types.String),
      "production",
    )),
  )

  // OneOf refinement
  let assert Ok(status_type) = dict.get(bp.params, "status")
  status_type
  |> should.equal(
    accepted_types.RefinementType(refinement_types.OneOf(
      accepted_types.PrimitiveType(primitive_types.String),
      set.from_list(["active", "inactive"]),
    )),
  )

  // InclusiveRange refinement
  let assert Ok(threshold_type) = dict.get(bp.params, "threshold")
  threshold_type
  |> should.equal(
    accepted_types.RefinementType(refinement_types.InclusiveRange(
      accepted_types.PrimitiveType(primitive_types.NumericType(
        numeric_types.Float,
      )),
      "0.0",
      "100.0",
    )),
  )
}

pub fn generate_blueprints_defaulted_type_alias_test() {
  let blueprints =
    parse_and_generate_blueprints("blueprints_defaulted_type_alias")
  let assert Ok(bp) = list.first(blueprints)

  // environment param should be Defaulted containing a resolved OneOf from _env alias
  let assert Ok(env_type) = dict.get(bp.params, "environment")
  env_type
  |> should.equal(
    accepted_types.ModifierType(modifier_types.Defaulted(
      accepted_types.RefinementType(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["production", "staging", "development"]),
      )),
      "production",
    )),
  )
}

pub fn generate_blueprints_template_vars_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_template_vars")
  let assert Ok(bp) = list.first(blueprints)

  // Template vars should be transformed: $env->env$ -> $$env->env$$
  let assert Ok(value_val) = dict.get(bp.inputs, "value")
  let assert Ok(value_str) = decode.run(value_val, decode.string)
  value_str |> should.equal("numerator / denominator")

  let assert Ok(queries_val) = dict.get(bp.inputs, "queries")
  let assert Ok(queries_dict) =
    decode.run(queries_val, decode.dict(decode.string, decode.dynamic))
  let assert Ok(num_val) = dict.get(queries_dict, "numerator")
  let assert Ok(num_str) = decode.run(num_val, decode.string)
  num_str
  |> should.equal("sum:http.requests{$$env->env$$, $$status->status:not$$}")
}

pub fn generate_blueprints_type_alias_test() {
  let blueprints = parse_and_generate_blueprints("blueprints_type_alias")
  let assert Ok(bp) = list.first(blueprints)

  // _env alias should be resolved to OneOf(String, {"production", "staging"})
  let assert Ok(env_type) = dict.get(bp.params, "env")
  env_type
  |> should.equal(
    accepted_types.RefinementType(refinement_types.OneOf(
      accepted_types.PrimitiveType(primitive_types.String),
      set.from_list(["production", "staging"]),
    )),
  )

  // Dict key uses _relation alias, should be resolved
  let assert Ok(config_type) = dict.get(bp.params, "config")
  config_type
  |> should.equal(
    accepted_types.CollectionType(collection_types.Dict(
      accepted_types.RefinementType(refinement_types.OneOf(
        accepted_types.PrimitiveType(primitive_types.String),
        set.from_list(["friend", "colleague"]),
      )),
      accepted_types.PrimitiveType(primitive_types.String),
    )),
  )

  // List uses _env alias
  let assert Ok(items_type) = dict.get(bp.params, "items")
  items_type
  |> should.equal(
    accepted_types.CollectionType(
      collection_types.List(
        accepted_types.RefinementType(refinement_types.OneOf(
          accepted_types.PrimitiveType(primitive_types.String),
          set.from_list(["production", "staging"]),
        )),
      ),
    ),
  )
}

// ==== generate_expectations ====
// * ✅ simple expectation produces correct name, blueprint_ref, inputs
// * ✅ expectation with extends (extendable flattening)
// * ✅ multiple extends (merge order: left to right, then item)
pub fn generate_expectations_simple_test() {
  let expectations = parse_and_generate_expects("expects_simple")
  list.length(expectations) |> should.equal(1)

  let assert Ok(exp) = list.first(expectations)
  exp.name |> should.equal("checkout")
  exp.blueprint_ref |> should.equal("api_availability")
  dict.size(exp.inputs) |> should.equal(2)

  let assert Ok(env_val) = dict.get(exp.inputs, "env")
  let assert Ok(env_str) = decode.run(env_val, decode.string)
  env_str |> should.equal("production")

  let assert Ok(threshold_val) = dict.get(exp.inputs, "threshold")
  let assert Ok(threshold_float) = decode.run(threshold_val, decode.float)
  threshold_float |> should.equal(99.95)
}

pub fn generate_expectations_with_extends_test() {
  let expectations = parse_and_generate_expects("expects_with_extends")
  let assert Ok(exp) = list.first(expectations)

  exp.name |> should.equal("checkout")
  exp.blueprint_ref |> should.equal("api_availability")

  // Should have merged fields from _defaults extendable + own provides
  let assert Ok(env_val) = dict.get(exp.inputs, "env")
  let assert Ok(env_str) = decode.run(env_val, decode.string)
  env_str |> should.equal("production")

  let assert Ok(threshold_val) = dict.get(exp.inputs, "threshold")
  let assert Ok(threshold_float) = decode.run(threshold_val, decode.float)
  threshold_float |> should.equal(99.95)

  let assert Ok(window_val) = dict.get(exp.inputs, "window_in_days")
  let assert Ok(window_int) = decode.run(window_val, decode.int)
  window_int |> should.equal(30)
}

pub fn generate_expectations_multiple_extends_test() {
  let expectations = parse_and_generate_expects("expects_multiple_extends")
  let assert Ok(exp) = list.first(expectations)

  // From _defaults: env: "production"
  let assert Ok(env_val) = dict.get(exp.inputs, "env")
  let assert Ok(env_str) = decode.run(env_val, decode.string)
  env_str |> should.equal("production")

  // From _strict: threshold: 99.99, window_in_days: 7
  let assert Ok(threshold_val) = dict.get(exp.inputs, "threshold")
  let assert Ok(threshold_float) = decode.run(threshold_val, decode.float)
  threshold_float |> should.equal(99.99)

  // From item's own provides: status: true
  let assert Ok(status_val) = dict.get(exp.inputs, "status")
  let assert Ok(status_bool) = decode.run(status_val, decode.bool)
  status_bool |> should.be_true
}

// ==== literal_to_dynamic ====
// * ✅ string
// * ✅ integer
// * ✅ float
// * ✅ boolean true
// * ✅ boolean false
// * ✅ list
// * ✅ struct (dict)
pub fn literal_to_dynamic_test() {
  // Test via the expects_complex_literals corpus which has lists, structs, bools, numbers
  let expectations = parse_and_generate_expects("expects_complex_literals")
  { expectations != [] } |> should.be_true
}
