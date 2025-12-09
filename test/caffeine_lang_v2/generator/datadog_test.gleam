import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/generator/datadog
import caffeine_lang_v2/middle_end/semantic_analyzer
import caffeine_lang_v2/middle_end/vendor
import gleam/dict
import gleam/dynamic
import gleam/list
import gleam/option
import gleeunit/should
import simplifile

// ==== Helpers ====
fn corpus_path(file_name: String) {
  "test/caffeine_lang_v2/corpus/generator/" <> file_name <> ".tf"
}

fn read_corpus(file_name: String) -> String {
  let assert Ok(content) = simplifile.read(corpus_path(file_name))
  content
}

// ==== generate_terraform ====
// * ✅ simple SLO with numerator/denominator queries
// * ✅ SLO with resolved template queries (tags filled in)
// * ✅ multiple SLOs generate multiple resources
pub fn generate_terraform_test() {
  [
    // simple SLO with numerator/denominator queries
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          "org/team/auth/latency_slo",
          "SLO",
          [
            helpers.ValueTuple(
              "vendor",
              helpers.String,
              dynamic.string("datadog"),
            ),
            helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              helpers.Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              helpers.Dict(helpers.String, helpers.String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{*}"),
                ),
              ]),
            ),
          ],
          option.Some(vendor.Datadog),
        ),
      ],
      "simple_slo",
    ),
    // SLO with resolved template queries (tags filled in)
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          "org/team/auth/latency_slo",
          "SLO",
          [
            helpers.ValueTuple(
              "vendor",
              helpers.String,
              dynamic.string("datadog"),
            ),
            helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              helpers.Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              helpers.Dict(helpers.String, helpers.String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{env:production,status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{env:production}"),
                ),
              ]),
            ),
          ],
          option.Some(vendor.Datadog),
        ),
      ],
      "resolved_templates",
    ),
    // multiple SLOs generate multiple resources
    #(
      [
        semantic_analyzer.IntermediateRepresentation(
          "org/team/auth/latency_slo",
          "SLO",
          [
            helpers.ValueTuple(
              "vendor",
              helpers.String,
              dynamic.string("datadog"),
            ),
            helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.9)),
            helpers.ValueTuple(
              "window_in_days",
              helpers.Integer,
              dynamic.int(30),
            ),
            helpers.ValueTuple(
              "queries",
              helpers.Dict(helpers.String, helpers.String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:http.requests{status:2xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:http.requests{*}"),
                ),
              ]),
            ),
          ],
          option.Some(vendor.Datadog),
        ),
        semantic_analyzer.IntermediateRepresentation(
          "org/team/api/availability_slo",
          "SLO",
          [
            helpers.ValueTuple(
              "vendor",
              helpers.String,
              dynamic.string("datadog"),
            ),
            helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.5)),
            helpers.ValueTuple(
              "window_in_days",
              helpers.Integer,
              dynamic.int(7),
            ),
            helpers.ValueTuple(
              "queries",
              helpers.Dict(helpers.String, helpers.String),
              dynamic.properties([
                #(
                  dynamic.string("numerator"),
                  dynamic.string("sum:api.requests{!status:5xx}"),
                ),
                #(
                  dynamic.string("denominator"),
                  dynamic.string("sum:api.requests{*}"),
                ),
              ]),
            ),
          ],
          option.Some(vendor.Datadog),
        ),
      ],
      "multiple_slos",
    ),
  ]
  |> list.each(fn(pair) {
    let #(input, corpus_file) = pair
    let expected = read_corpus(corpus_file)
    datadog.generate_terraform(input) |> should.equal(expected)
  })
}

// ==== sanitize_resource_name ====
// * ✅ replaces slashes with underscores
// * ✅ replaces spaces with underscores
// * ✅ handles simple names without modification
pub fn sanitize_resource_name_test() {
  [
    // replaces slashes with underscores
    #("org/team/auth/latency", "org_team_auth_latency"),
    // replaces spaces with underscores
    #("my slo name", "my_slo_name"),
    // handles simple names without modification
    #("simple_name", "simple_name"),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    datadog.sanitize_resource_name(input) |> should.equal(expected)
  })
}

// ==== window_to_timeframe ====
// * ✅ 7 -> "7d"
// * ✅ 30 -> "30d"
// * ✅ 90 -> "90d"
pub fn window_to_timeframe_test() {
  [
    // 7 -> "7d"
    #(7, "7d"),
    // 30 -> "30d"
    #(30, "30d"),
    // 90 -> "90d"
    #(90, "90d"),
  ]
  |> list.each(fn(pair) {
    let #(input, expected) = pair
    datadog.window_to_timeframe(input) |> should.equal(expected)
  })
}

// ==== extract_string ====
// * ✅ extracts String ValueTuple
// * ✅ returns Error for missing label
pub fn extract_string_test() {
  [
    // extracts String ValueTuple
    #(
      [helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog"))],
      "vendor",
      Ok("datadog"),
    ),
    // returns Error for missing label
    #(
      [helpers.ValueTuple("vendor", helpers.String, dynamic.string("datadog"))],
      "missing",
      Error(Nil),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(values, label, expected) = tuple
    datadog.extract_string(values, label) |> should.equal(expected)
  })
}

// ==== extract_float ====
// * ✅ extracts Float ValueTuple
// * ✅ returns Error for missing label
pub fn extract_float_test() {
  [
    // extracts Float ValueTuple
    #(
      [helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.9))],
      "threshold",
      Ok(99.9),
    ),
    // returns Error for missing label
    #(
      [helpers.ValueTuple("threshold", helpers.Float, dynamic.float(99.9))],
      "missing",
      Error(Nil),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(values, label, expected) = tuple
    datadog.extract_float(values, label) |> should.equal(expected)
  })
}

// ==== extract_int ====
// * ✅ extracts Integer ValueTuple
// * ✅ returns Error for missing label
pub fn extract_int_test() {
  [
    // extracts Integer ValueTuple
    #(
      [helpers.ValueTuple("window_in_days", helpers.Integer, dynamic.int(30))],
      "window_in_days",
      Ok(30),
    ),
    // returns Error for missing label
    #(
      [helpers.ValueTuple("window_in_days", helpers.Integer, dynamic.int(30))],
      "missing",
      Error(Nil),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(values, label, expected) = tuple
    datadog.extract_int(values, label) |> should.equal(expected)
  })
}

// ==== extract_dict_string_string ====
// * ✅ extracts Dict(String, String) ValueTuple
// * ✅ returns Error for missing label
pub fn extract_dict_string_string_test() {
  [
    // extracts Dict(String, String) ValueTuple
    #(
      [
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([
            #(dynamic.string("numerator"), dynamic.string("sum:good")),
            #(dynamic.string("denominator"), dynamic.string("sum:total")),
          ]),
        ),
      ],
      "queries",
      Ok(
        dict.from_list([#("numerator", "sum:good"), #("denominator", "sum:total")]),
      ),
    ),
    // returns Error for missing label
    #(
      [
        helpers.ValueTuple(
          "queries",
          helpers.Dict(helpers.String, helpers.String),
          dynamic.properties([]),
        ),
      ],
      "missing",
      Error(Nil),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(values, label, expected) = tuple
    datadog.extract_dict_string_string(values, label) |> should.equal(expected)
  })
}
