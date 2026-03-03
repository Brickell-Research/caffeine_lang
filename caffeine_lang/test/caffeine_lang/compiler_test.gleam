import caffeine_lang/compiler.{type CompilationOutput}
import caffeine_lang/constants
import caffeine_lang/source_file.{
  type ExpectationSource, type SourceFile, SourceFile,
}
import gleam/list
import gleam/result
import gleam/string
import simplifile
import test_helpers

fn corpus_path(file_name: String) -> String {
  "test/caffeine_lang/corpus/compiler/" <> file_name
}

fn read_corpus(file_name: String) -> String {
  let assert Ok(content) = simplifile.read(corpus_path(file_name))
  // Replace version placeholder with actual version constant
  string.replace(content, "{{VERSION}}", constants.version)
}

fn read_source_file(path: String) -> SourceFile(a) {
  let assert Ok(content) = simplifile.read(path)
  SourceFile(path: path, content: content)
}

fn find_caffeine_files(dir: String) -> List(String) {
  let assert Ok(entries) = simplifile.read_directory(dir)
  entries
  |> list.flat_map(fn(entry) {
    let path = dir <> "/" <> entry
    case simplifile.is_directory(path) {
      Ok(True) -> find_caffeine_files(path)
      _ ->
        case string.ends_with(entry, ".caffeine") {
          True -> [path]
          False -> []
        }
    }
  })
}

fn read_expectations_dir(dir: String) -> List(SourceFile(ExpectationSource)) {
  find_caffeine_files(dir)
  |> list.map(read_source_file)
}

// ==== compile ====
// * ✅ happy path - none
// * ✅ happy path - single
// * ✅ happy path - multiple (3 SLOs across 2 teams)
// * ✅ happy path - type alias (E2E test with type alias in Requiring)
pub fn compile_test() {
  [
    // happy path - none
    #(
      "happy path - none",
      #(
        corpus_path("happy_path_no_expectations_blueprints/datadog.caffeine"),
        corpus_path("happy_path_no_expectations"),
      ),
      Ok(read_corpus("happy_path_no_expectations_output.tf")),
    ),
    // happy path - single
    #(
      "happy path - single",
      #(
        corpus_path("happy_path_single_blueprints/datadog.caffeine"),
        corpus_path("happy_path_single_expectations"),
      ),
      Ok(read_corpus("happy_path_single_output.tf")),
    ),
    // happy path - multiple (3 SLOs across 2 teams)
    #(
      "happy path - multiple (3 SLOs across 2 teams)",
      #(
        corpus_path("happy_path_multiple_blueprints/datadog.caffeine"),
        corpus_path("happy_path_multiple_expectations"),
      ),
      Ok(read_corpus("happy_path_multiple_output.tf")),
    ),
    // happy path - type alias (E2E test with type alias in Requiring)
    #(
      "happy path - type alias (E2E test with type alias in Requiring)",
      #(
        corpus_path("happy_path_type_alias_blueprints/datadog.caffeine"),
        corpus_path("happy_path_type_alias_expectations"),
      ),
      Ok(read_corpus("happy_path_type_alias_output.tf")),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(input_blueprints_path, input_expectations_dir) = input
    compiler.compile(
      read_source_file(input_blueprints_path),
      read_expectations_dir(input_expectations_dir),
    )
    |> result.map(fn(output) { output.terraform })
  })
}

fn contains_all_substrings(
  result: Result(CompilationOutput, a),
  substrings: List(String),
) {
  case result {
    Ok(output) ->
      list.all(substrings, fn(s) { string.contains(output.terraform, s) })
    Error(_) -> False
  }
}

// ==== compile_from_strings ====
// * ✅ happy path - single expectation with templated queries
// * ✅ happy path - path extraction (org/team/service from file path)
// * ✅ happy path - time_slice SLO expression
// * ✅ sad path   - invalid blueprint DSL
// * ✅ sad path   - invalid expectations DSL
// * ✅ sad path   - missing blueprint reference
pub fn compile_from_strings_test() {
  // happy paths - check that output contains expected substrings
  [
    // single expectation with templated queries
    #(
      "happy path - single expectation with templated queries",
      #(
        "Blueprints
  \"api_availability\" success_rate(numerator / denominator):
    Requiring { env: String, status: Boolean, threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals {
      numerator: \"sum:http.requests{$env->env$ AND $status->status.not$}\",
      denominator: \"sum:http.requests{$env->env$}\"
    }
",
        "Expectations for \"api_availability\"
  \"checkout_availability\":
    Provides {
      env: \"production\",
      status: true,
      threshold: 99.95,
      window_in_days: 30
    }
",
        "acme/payments/slos.caffeine",
        [
          "datadog_service_level_objective",
          "checkout_availability",
          "sum:http.requests",
        ],
      ),
      True,
    ),
    // path extraction (org/team/service from file path)
    #(
      "happy path - path extraction (org/team/service from file path)",
      #(
        "Blueprints
  \"simple_slo\" success_rate(numerator / denominator):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals { numerator: \"count:test\", denominator: \"count:test\" }
",
        "Expectations for \"simple_slo\"
  \"my_slo\":
    Provides {
      threshold: 99.0,
      window_in_days: 7
    }
",
        "myorg/myteam/myservice.caffeine",
        ["org:myorg", "team:myteam", "service:myservice"],
      ),
      True,
    ),
    // time_slice SLO expression
    #(
      "happy path - time_slice SLO expression",
      #(
        "Blueprints
  \"cpu_slo\" time_slice(\"avg:system.cpu.user{$env->env$} > 99.5 per 300s\"):
    Requiring { env: String, threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals { }
",
        "Expectations for \"cpu_slo\"
  \"cpu_availability\":
    Provides {
      env: \"production\",
      threshold: 99.9,
      window_in_days: 30
    }
",
        "acme/infra/slos.caffeine",
        [
          "datadog_service_level_objective",
          "cpu_availability",
          "type = \"time_slice\"",
          "sli_specification",
          "time_slice",
          "comparator = \">\"",
          "query_interval_seconds = 300",
          "threshold = 99.5",
          "avg:system.cpu.user{env:production}",
        ],
      ),
      True,
    ),
    // sad path - invalid blueprint DSL
    #(
      "sad path - invalid blueprint DSL",
      #(
        "this is not valid caffeine syntax !!!",
        "Expectations for \"x\"
  \"y\":
    Provides {}
",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - invalid expectations DSL
    #(
      "sad path - invalid expectations DSL",
      #(
        "Blueprints
  \"api_availability\" success_rate(1):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals { numerator: \"1\", denominator: \"1\" }
",
        "not valid caffeine syntax !!!",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - missing blueprint reference
    #(
      "sad path - missing blueprint reference",
      #(
        "Blueprints
  \"some_blueprint\" success_rate(1):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals { numerator: \"1\", denominator: \"1\" }
",
        "Expectations for \"nonexistent_blueprint\"
  \"my_slo\":
    Provides {}
",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - invalid dependency reference (target does not exist)
    #(
      "sad path - invalid dependency reference (target does not exist)",
      #(
        "Blueprints
  \"slo_with_deps\" success_rate(numerator / denominator):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) }, relations: { hard: List(String), soft: List(String) } }
    signals { numerator: \"count:test\", denominator: \"count:test\", relations: { hard: [\"nonexistent.org.team.slo\"] } }
",
        "Expectations for \"slo_with_deps\"
  \"my_slo\":
    Provides {
      threshold: 99.0,
      window_in_days: 7
    }
",
        "myorg/myteam/myservice.caffeine",
        [],
      ),
      False,
    ),
    // sad path - invalid dependency format (not 4 parts)
    #(
      "sad path - invalid dependency format (not 4 parts)",
      #(
        "Blueprints
  \"slo_with_deps\" success_rate(numerator / denominator):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) }, relations: { hard: List(String), soft: List(String) } }
    signals { numerator: \"count:test\", denominator: \"count:test\", relations: { hard: [\"invalid_format\"] } }
",
        "Expectations for \"slo_with_deps\"
  \"my_slo\":
    Provides {
      threshold: 99.0,
      window_in_days: 7
    }
",
        "myorg/myteam/myservice.caffeine",
        [],
      ),
      False,
    ),
    // sad path - self-reference in dependency
    #(
      "sad path - self-reference in dependency",
      #(
        "Blueprints
  \"slo_with_deps\" success_rate(numerator / denominator):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) }, relations: { hard: List(String), soft: List(String) } }
    signals { numerator: \"count:test\", denominator: \"count:test\", relations: { hard: [\"myorg.myteam.myservice.my_slo\"] } }
",
        "Expectations for \"slo_with_deps\"
  \"my_slo\":
    Provides {
      threshold: 99.0,
      window_in_days: 7
    }
",
        "myorg/myteam/myservice.caffeine",
        [],
      ),
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(blueprints_src, expectations_src, path, expected_substrings) = input
    let result =
      compiler.compile_from_strings(blueprints_src, expectations_src, path)
    case expected_substrings {
      [] ->
        case result {
          Ok(_) -> True
          Error(_) -> False
        }
      _ -> contains_all_substrings(result, expected_substrings)
    }
  })
}

// ==== compile_from_strings (Honeycomb) ====
// * ✅ happy path - single Honeycomb SLO
// * ✅ sad path   - Honeycomb with invalid window (out of 1-90 range)
pub fn compile_from_strings_honeycomb_test() {
  [
    // happy path - single Honeycomb SLO
    #(
      "happy path - single Honeycomb SLO",
      #(
        "Blueprints
  \"honeycomb_availability\" success_rate(sli):
    Requiring { env: String, threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals {
      sli: \"HEATMAP(duration_ms)\"
    }
",
        "Expectations for \"honeycomb_availability\"
  \"api_success_rate\":
    Provides {
      env: \"production\",
      threshold: 99.5,
      window_in_days: 14
    }
",
        "acme/platform/payments.caffeine",
        [
          "honeycombio_slo",
          "honeycombio_derived_column",
          "api_success_rate",
          "var.honeycomb_dataset",
          "var.honeycomb_api_key",
          "target_percentage = 99.5",
          "time_period = 14",
        ],
      ),
      True,
    ),
    // sad path - Honeycomb with invalid window (out of 1-90 range)
    #(
      "sad path - Honeycomb with invalid window (out of 1-90 range)",
      #(
        "Blueprints
  \"hc_blueprint\" success_rate(sli):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals {
      sli: \"HEATMAP(duration_ms)\"
    }
",
        "Expectations for \"hc_blueprint\"
  \"hc_slo\":
    Provides {
      threshold: 99.5,
      window_in_days: 91
    }
",
        "acme/platform/payments.caffeine",
        [],
      ),
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(blueprints_src, expectations_src, path, expected_substrings) = input
    let result =
      compiler.compile_from_strings_with_blueprint_path(
        blueprints_src,
        expectations_src,
        path,
        "vendor/honeycomb.caffeine",
      )
    case expected_substrings {
      [] ->
        case result {
          Ok(_) -> True
          Error(_) -> False
        }
      _ -> contains_all_substrings(result, expected_substrings)
    }
  })
}

// ==== compile_from_strings (Dynatrace) ====
// * ✅ happy path - single Dynatrace SLO
// * ✅ sad path   - Dynatrace with invalid window (out of 1-90 range)
pub fn compile_from_strings_dynatrace_test() {
  [
    // happy path - single Dynatrace SLO
    #(
      "happy path - single Dynatrace SLO",
      #(
        "Blueprints
  \"dynatrace_availability\" success_rate(sli):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals {
      sli: \"builtin:service.requestCount.server:splitBy()\"
    }
",
        "Expectations for \"dynatrace_availability\"
  \"api_success_rate\":
    Provides {
      threshold: 99.5,
      window_in_days: 30
    }
",
        "acme/platform/payments.caffeine",
        [
          "dynatrace_slo_v2",
          "api_success_rate",
          "var.dynatrace_env_url",
          "var.dynatrace_api_token",
          "evaluation_window = \"-30d\"",
          "target_success = 99.5",
          "evaluation_type = \"AGGREGATE\"",
        ],
      ),
      True,
    ),
    // sad path - Dynatrace with invalid window (out of 1-90 range)
    #(
      "sad path - Dynatrace with invalid window (out of 1-90 range)",
      #(
        "Blueprints
  \"dt_blueprint\" success_rate(sli):
    Requiring { threshold: Float, window_in_days: Integer { x | x in ( 1..90 ) } }
    signals {
      sli: \"builtin:service.requestCount.server:splitBy()\"
    }
",
        "Expectations for \"dt_blueprint\"
  \"dt_slo\":
    Provides {
      threshold: 99.5,
      window_in_days: 91
    }
",
        "acme/platform/payments.caffeine",
        [],
      ),
      False,
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(blueprints_src, expectations_src, path, expected_substrings) = input
    let result =
      compiler.compile_from_strings_with_blueprint_path(
        blueprints_src,
        expectations_src,
        path,
        "vendor/dynatrace.caffeine",
      )
    case expected_substrings {
      [] ->
        case result {
          Ok(_) -> True
          Error(_) -> False
        }
      _ -> contains_all_substrings(result, expected_substrings)
    }
  })
}
