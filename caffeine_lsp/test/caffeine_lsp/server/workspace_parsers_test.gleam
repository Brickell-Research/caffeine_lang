import caffeine_lsp/server/workspace_parsers
import gleam/dict
import gleam/set
import gleeunit/should

// ==== extract_blueprint_names ====
// * ✅ extracts names from blueprint file
// * ✅ returns empty for non-blueprint file
// * ✅ skips comment lines

pub fn extract_blueprint_names_basic_test() {
  let text =
    "Blueprints for \"Availability SLO\"
  Requires:
    _env (Environment): String
  Provides:
    * \"API Latency\"
      target: 99.9
    * \"Error Rate\"
      target: 99.5
"
  let names = workspace_parsers.extract_blueprint_names(text)
  names |> should.equal(["API Latency", "Error Rate"])
}

pub fn extract_blueprint_names_non_blueprint_test() {
  let text =
    "Expectations for \"Availability SLO\"
  * \"My Expectation\"
    env: prod
"
  workspace_parsers.extract_blueprint_names(text)
  |> should.equal([])
}

pub fn extract_blueprint_names_skips_comments_test() {
  let text =
    "Blueprints for \"SLO\"
  # * \"Commented Out\"
  * \"Real Item\"
"
  workspace_parsers.extract_blueprint_names(text)
  |> should.equal(["Real Item"])
}

// ==== extract_referenced_blueprint_names ====
// * ✅ extracts referenced blueprint names
// * ✅ returns empty when no expectations

pub fn extract_referenced_blueprint_names_test() {
  let text =
    "Expectations for \"Availability SLO\"
  * \"My API\"
    env: prod

Expectations for \"Latency SLO\"
  * \"Another\"
    env: staging
"
  workspace_parsers.extract_referenced_blueprint_names(text)
  |> should.equal(["Availability SLO", "Latency SLO"])
}

pub fn extract_referenced_blueprint_names_empty_test() {
  let text =
    "Blueprints for \"SLO\"
  * \"Item\"
"
  workspace_parsers.extract_referenced_blueprint_names(text)
  |> should.equal([])
}

// ==== extract_path_prefix ====
// * ✅ extracts last 3 segments
// * ✅ handles short path

pub fn extract_path_prefix_test() {
  workspace_parsers.extract_path_prefix("/data/acme/backend/api.caffeine")
  |> should.equal(#("acme", "backend", "api"))
}

pub fn extract_path_prefix_strips_extension_test() {
  workspace_parsers.extract_path_prefix("/data/org/team/svc.caffeine")
  |> should.equal(#("org", "team", "svc"))
}

pub fn extract_path_prefix_short_path_test() {
  workspace_parsers.extract_path_prefix("file.caffeine")
  |> should.equal(#("unknown", "unknown", "unknown"))
}

// ==== extract_expectation_identifiers ====
// * ✅ extracts dotted identifiers
// * ✅ returns empty for blueprint files

pub fn extract_expectation_identifiers_test() {
  let text =
    "Expectations for \"SLO\"
  * \"My API\"
    env: prod
"
  let uri = "file:///data/acme/backend/api.caffeine"
  let result = workspace_parsers.extract_expectation_identifiers(text, uri)
  result
  |> dict.get("My API")
  |> should.equal(Ok("acme.backend.api.My API"))
}

pub fn extract_expectation_identifiers_empty_test() {
  let text =
    "Blueprints for \"SLO\"
  * \"Item\"
"
  workspace_parsers.extract_expectation_identifiers(
    text,
    "file:///a/b/c.caffeine",
  )
  |> should.equal(dict.new())
}

// ==== find_blueprint_item_location ====
// * ✅ finds item location
// * ✅ returns error when not found

pub fn find_blueprint_item_location_test() {
  let text =
    "Blueprints for \"SLO\"
  Requires:
    _env (Environment): String
  Provides:
    * \"API Latency\"
      target: 99.9
"
  let result =
    workspace_parsers.find_blueprint_item_location(text, "API Latency")
  let assert Ok(#(line, col, name_len)) = result
  line |> should.equal(4)
  col |> should.equal(7)
  name_len |> should.equal(11)
}

pub fn find_blueprint_item_location_not_found_test() {
  let text =
    "Blueprints for \"SLO\"
  * \"Item\"
"
  workspace_parsers.find_blueprint_item_location(text, "Missing")
  |> should.be_error()
}

// ==== apply_index_updates ====
// * ✅ adds new blueprints to empty index
// * ✅ detects changes

pub fn apply_index_updates_new_blueprints_test() {
  let text =
    "Blueprints for \"SLO\"
  * \"Item A\"
  * \"Item B\"
"
  let #(bp_index, _exp_index, changed) =
    workspace_parsers.apply_index_updates(
      "file:///test.caffeine",
      text,
      dict.new(),
      dict.new(),
    )
  changed |> should.be_true()
  dict.get(bp_index, "file:///test.caffeine")
  |> should.equal(Ok(set.from_list(["Item A", "Item B"])))
}

pub fn apply_index_updates_no_change_test() {
  let text =
    "Blueprints for \"SLO\"
  * \"Item\"
"
  let existing_bp =
    dict.from_list([
      #("file:///test.caffeine", set.from_list(["Item"])),
    ])
  let #(_bp_index, _exp_index, changed) =
    workspace_parsers.apply_index_updates(
      "file:///test.caffeine",
      text,
      existing_bp,
      dict.new(),
    )
  changed |> should.be_false()
}
