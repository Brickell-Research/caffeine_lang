import caffeine_lang/common/constants
import caffeine_lang/common/source_file.{type SourceFile, SourceFile}
import caffeine_lang/core/compilation_configuration
import caffeine_lang/core/compiler
import caffeine_lang/core/logger
import gleam/list
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

fn read_source_file(path: String) -> SourceFile {
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

fn read_expectations_dir(dir: String) -> List(SourceFile) {
  find_caffeine_files(dir)
  |> list.map(read_source_file)
}

// ==== compile ====
// * ✅ happy path - none
// * ✅ happy path - single
// * ✅ happy path - multiple (3 SLOs across 2 teams)
// * ✅ happy path - type alias (E2E test with type alias in Requires)
pub fn compile_test() {
  let config =
    compilation_configuration.CompilationConfig(log_level: logger.Minimal)
  [
    // happy path - none
    #(
      #(
        corpus_path("happy_path_no_expectations_blueprints.caffeine"),
        corpus_path("happy_path_no_expectations"),
      ),
      Ok(read_corpus("happy_path_no_expectations_output.tf")),
    ),
    // happy path - single
    #(
      #(
        corpus_path("happy_path_single_blueprints.caffeine"),
        corpus_path("happy_path_single_expectations"),
      ),
      Ok(read_corpus("happy_path_single_output.tf")),
    ),
    // happy path - multiple (3 SLOs across 2 teams)
    #(
      #(
        corpus_path("happy_path_multiple_blueprints.caffeine"),
        corpus_path("happy_path_multiple_expectations"),
      ),
      Ok(read_corpus("happy_path_multiple_output.tf")),
    ),
    // happy path - type alias (E2E test with type alias in Requires)
    #(
      #(
        corpus_path("happy_path_type_alias_blueprints.caffeine"),
        corpus_path("happy_path_type_alias_expectations"),
      ),
      Ok(read_corpus("happy_path_type_alias_output.tf")),
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(input_blueprints_path, input_expectations_dir) = input
    compiler.compile(
      read_source_file(input_blueprints_path),
      read_expectations_dir(input_expectations_dir),
      config,
    )
  })
}

fn contains_all_substrings(result: Result(String, a), substrings: List(String)) {
  case result {
    Ok(terraform) ->
      list.all(substrings, fn(s) { string.contains(terraform, s) })
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
      #(
        "Blueprints for \"SLO\"
  * \"api_availability\":
    Requires { env: String, status: Boolean }
    Provides {
      vendor: \"datadog\",
      evaluation: \"numerator / denominator\",
      indicators: {
        numerator: \"sum:http.requests{$env->env$ AND $status->status.not$}\",
        denominator: \"sum:http.requests{$env->env$}\"
      }
    }
",
        "Expectations for \"api_availability\"
  * \"checkout_availability\":
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
      #(
        "Blueprints for \"SLO\"
  * \"simple_slo\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" }
    }
",
        "Expectations for \"simple_slo\"
  * \"my_slo\":
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
      #(
        "Blueprints for \"SLO\"
  * \"cpu_slo\":
    Requires { env: String }
    Provides {
      vendor: \"datadog\",
      evaluation: \"time_slice(avg:system.cpu.user{$env->env$} > 99.5 per 300s)\",
      indicators: {}
    }
",
        "Expectations for \"cpu_slo\"
  * \"cpu_availability\":
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
      #(
        "this is not valid caffeine syntax !!!",
        "Expectations for \"x\"
  * \"y\":
    Provides {}
",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - invalid expectations DSL
    #(
      #(
        "Blueprints for \"SLO\"
  * \"api_availability\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"1\",
      indicators: { numerator: \"1\", denominator: \"1\" }
    }
",
        "not valid caffeine syntax !!!",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - missing blueprint reference
    #(
      #(
        "Blueprints for \"SLO\"
  * \"some_blueprint\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"1\",
      indicators: { numerator: \"1\", denominator: \"1\" }
    }
",
        "Expectations for \"nonexistent_blueprint\"
  * \"my_slo\":
    Provides {}
",
        "playground/demo/service.caffeine",
        [],
      ),
      False,
    ),
    // sad path - invalid dependency reference (target does not exist)
    #(
      #(
        "Blueprints for \"SLO\" + \"DependencyRelations\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      relations: { hard: [\"nonexistent.org.team.slo\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
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
      #(
        "Blueprints for \"SLO\" + \"DependencyRelations\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      relations: { hard: [\"invalid_format\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
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
      #(
        "Blueprints for \"SLO\" + \"DependencyRelations\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      vendor: \"datadog\",
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      relations: { hard: [\"myorg.myteam.myservice.my_slo\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
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
  |> test_helpers.array_based_test_executor_1(fn(input) {
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
