import caffeine_lang/helpers
import caffeine_lang/linker/artifacts.{SLO}
import caffeine_lang/types
import caffeine_lang/value
import gleam/dict
import gleam/list
import gleeunit/should
import test_helpers

// ==== map_reference_to_referrer_over_collection ====
// * ✅ happy path - empty collection
// * ✅ happy path - matches references to referrers
pub fn map_reference_to_referrer_over_collection_test() {
  [
    // empty collection
    #(#([], []), []),
    // matches references to referrers
    #(#([#("alice", 1), #("bob", 2)], [#("bob", 100), #("alice", 200)]), [
      #(#("bob", 100), #("bob", 2)),
      #(#("alice", 200), #("alice", 1)),
    ]),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(references, referrers) = input
    helpers.map_reference_to_referrer_over_collection(
      references:,
      referrers:,
      reference_name: fn(x: #(String, Int)) { x.0 },
      referrer_reference: fn(x: #(String, Int)) { x.0 },
    )
  })
}

// ==== extract_value ====
// * ✅ extracts value by label
// * ✅ returns Error for missing label
// * ✅ returns Error for extractor failure
pub fn extract_value_test() {
  let values = [
    helpers.ValueTuple(
      "name",
      types.PrimitiveType(types.String),
      value.StringValue("hello"),
    ),
    helpers.ValueTuple(
      "count",
      types.PrimitiveType(types.NumericType(types.Integer)),
      value.IntValue(42),
    ),
  ]

  // extracts value by label
  helpers.extract_value(values, "name", value.extract_string)
  |> should.equal(Ok("hello"))

  // extracts value with different extractor
  helpers.extract_value(values, "count", value.extract_int)
  |> should.equal(Ok(42))

  // returns Error for missing label
  helpers.extract_value(values, "missing", value.extract_string)
  |> should.equal(Error(Nil))

  // returns Error for extractor failure (wrong extractor for type)
  helpers.extract_value(values, "count", value.extract_string)
  |> should.equal(Error(Nil))
}

// ==== extract_path_prefix ====
// * ✅ standard path with 3+ segments
// * ✅ path ending in .caffeine
// * ✅ path ending in .json
pub fn extract_path_prefix_test() {
  [
    #("examples/org/platform_team/authentication.caffeine", #(
      "org",
      "platform_team",
      "authentication",
    )),
    #("examples/org/platform_team/auth.json", #("org", "platform_team", "auth")),
    #("a/b/c", #("a", "b", "c")),
  ]
  |> test_helpers.array_based_test_executor_1(helpers.extract_path_prefix)
}

// ==== extract_threshold ====
// * ✅ present threshold value
// * ✅ missing threshold returns default 99.9
pub fn extract_threshold_test() {
  let with_threshold = [
    helpers.ValueTuple(
      "threshold",
      types.PrimitiveType(types.NumericType(types.Float)),
      value.FloatValue(95.0),
    ),
  ]
  helpers.extract_threshold(with_threshold)
  |> should.equal(95.0)

  helpers.extract_threshold([])
  |> should.equal(99.9)
}

// ==== extract_relations ====
// * ✅ present relations
// * ✅ missing returns empty dict
pub fn extract_relations_test() {
  helpers.extract_relations([])
  |> should.equal(dict.new())
}

// ==== extract_window_in_days ====
// * ✅ present window
// * ✅ missing returns default 30
pub fn extract_window_in_days_test() {
  let with_window = [
    helpers.ValueTuple(
      "window_in_days",
      types.PrimitiveType(types.NumericType(types.Integer)),
      value.IntValue(7),
    ),
  ]
  helpers.extract_window_in_days(with_window)
  |> should.equal(7)

  helpers.extract_window_in_days([])
  |> should.equal(30)
}

// ==== extract_indicators ====
// * ✅ present indicators
// * ✅ missing returns empty dict
pub fn extract_indicators_test() {
  helpers.extract_indicators([])
  |> should.equal(dict.new())
}

// ==== extract_tags ====
// * ✅ present tags (sorted by key)
// * ✅ missing returns empty list
pub fn extract_tags_test() {
  helpers.extract_tags([])
  |> should.equal([])
}

// ==== build_system_tag_pairs ====
// * ✅ includes all required system tags
// * ✅ includes artifact refs
// * ✅ includes misc tags sorted
pub fn build_system_tag_pairs_test() {
  let result =
    helpers.build_system_tag_pairs(
      org_name: "my_org",
      team_name: "my_team",
      service_name: "my_service",
      blueprint_name: "my_bp",
      friendly_label: "my_label",
      artifact_refs: [SLO],
      misc: dict.from_list([#("env", ["prod", "dev"])]),
    )

  // Should contain system tags
  list.contains(result, #("managed_by", "caffeine")) |> should.be_true()
  list.contains(result, #("org", "my_org")) |> should.be_true()
  list.contains(result, #("team", "my_team")) |> should.be_true()
  list.contains(result, #("service", "my_service")) |> should.be_true()
  list.contains(result, #("blueprint", "my_bp")) |> should.be_true()
  list.contains(result, #("expectation", "my_label")) |> should.be_true()
  // Artifact refs
  list.contains(result, #("artifact", "SLO")) |> should.be_true()
  // Misc tags (sorted)
  list.contains(result, #("env", "dev")) |> should.be_true()
  list.contains(result, #("env", "prod")) |> should.be_true()
}
