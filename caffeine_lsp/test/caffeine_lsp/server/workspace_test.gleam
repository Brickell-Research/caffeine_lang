import caffeine_lsp/server/workspace
import gleam/option
import gleam/set
import gleeunit/should

// ==== new ====
// * ✅ creates empty state

pub fn new_test() {
  let state = workspace.new()
  workspace.all_known_blueprints(state) |> should.equal([])
  workspace.all_known_expectation_identifiers(state) |> should.equal([])
  workspace.all_file_uris(state) |> should.equal([])
}

// ==== document lifecycle ====
// * ✅ open/get/close documents

pub fn document_lifecycle_test() {
  let state = workspace.new()
  let uri = "file:///test.caffeine"

  workspace.get_document(state, uri) |> should.equal(option.None)

  let state = workspace.document_opened(state, uri, "hello")
  workspace.get_document(state, uri) |> should.equal(option.Some("hello"))

  let state = workspace.document_changed(state, uri, "updated")
  workspace.get_document(state, uri) |> should.equal(option.Some("updated"))

  let state = workspace.document_closed(state, uri)
  workspace.get_document(state, uri) |> should.equal(option.None)
}

// ==== set_root ====
// * ✅ strips file:// prefix

pub fn set_root_strips_prefix_test() {
  let state =
    workspace.new()
    |> workspace.set_root("file:///home/user/project")
  state.root |> should.equal(option.Some("/home/user/project"))
}

pub fn set_root_keeps_plain_path_test() {
  let state =
    workspace.new()
    |> workspace.set_root("/home/user/project")
  state.root |> should.equal(option.Some("/home/user/project"))
}

// ==== update_indices_for_file ====
// * ✅ indexes blueprint names
// * ✅ indexes expectation identifiers
// * ✅ reports changed correctly

pub fn update_indices_blueprints_test() {
  let state = workspace.new()
  let uri = "file:///org/team/svc.caffeine"
  let text =
    "Blueprints for \"SLO\"
  * \"Item A\"
  * \"Item B\"
"
  let #(state, changed) = workspace.update_indices_for_file(state, uri, text)
  changed |> should.be_true()
  workspace.all_known_blueprints(state)
  |> set.from_list
  |> should.equal(set.from_list(["Item A", "Item B"]))
}

pub fn update_indices_expectations_test() {
  let state = workspace.new()
  let uri = "file:///data/acme/backend/api.caffeine"
  let text =
    "Expectations for \"SLO\"
  * \"My API\"
    env: prod
"
  let #(state, changed) = workspace.update_indices_for_file(state, uri, text)
  changed |> should.be_true()
  workspace.all_known_expectation_identifiers(state)
  |> should.equal(["acme.backend.api.My API"])
}

// ==== remove_file ====
// * ✅ removes from all indices

pub fn remove_file_test() {
  let state = workspace.new()
  let uri = "file:///org/team/svc.caffeine"
  let text =
    "Blueprints for \"SLO\"
  * \"Item\"
"
  let #(state, _) = workspace.update_indices_for_file(state, uri, text)
  workspace.all_known_blueprints(state) |> should.equal(["Item"])

  let #(state, removed) = workspace.remove_file(state, uri)
  removed |> should.be_true()
  workspace.all_known_blueprints(state) |> should.equal([])
}

// ==== find_cross_file_blueprint_def ====
// * ✅ finds definition across files

pub fn find_cross_file_blueprint_def_test() {
  let state = workspace.new()
  let uri = "file:///org/team/svc.caffeine"
  let text =
    "Blueprints for \"SLO\"
  Requires:
    _env (Environment): String
  Provides:
    * \"API Latency\"
      target: 99.9
"
  let state = workspace.document_opened(state, uri, text)
  let #(state, _) = workspace.update_indices_for_file(state, uri, text)

  case workspace.find_cross_file_blueprint_def(state, "API Latency") {
    option.Some(#(found_uri, line, col, name_len)) -> {
      found_uri |> should.equal(uri)
      line |> should.equal(4)
      col |> should.equal(7)
      name_len |> should.equal(11)
    }
    option.None -> should.fail()
  }
}

pub fn find_cross_file_blueprint_def_not_found_test() {
  let state = workspace.new()
  workspace.find_cross_file_blueprint_def(state, "Missing")
  |> should.equal(option.None)
}

// ==== all_validated_blueprints ====
// * ✅ returns empty initially
// * ✅ caching works (not dirty on second call)

pub fn all_validated_blueprints_empty_test() {
  let state = workspace.new()
  let #(_state, blueprints) = workspace.all_validated_blueprints(state)
  blueprints |> should.equal([])
}

pub fn all_validated_blueprints_caching_test() {
  let state = workspace.new()
  let #(state, _) = workspace.all_validated_blueprints(state)
  state.validated_blueprints_dirty |> should.be_false()
  // Second call should use cache.
  let #(state2, _) = workspace.all_validated_blueprints(state)
  state2.validated_blueprints_dirty |> should.be_false()
}
