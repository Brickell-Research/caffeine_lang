import caffeine_lang/common/constants
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
    compiler.compile(input_blueprints_path, input_expectations_dir, config)
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
// * ✅ sad path   - invalid blueprint JSON
// * ✅ sad path   - invalid expectations JSON
// * ✅ sad path   - missing blueprint reference
pub fn compile_from_strings_test() {
  // happy paths - check that output contains expected substrings
  [
    // single expectation with templated queries
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"api_availability\",
          \"artifact_refs\": [\"SLO\"],
          \"params\": { \"env\": \"String\", \"status\": \"Boolean\" },
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"numerator / denominator\",
            \"queries\": {
              \"numerator\": \"sum:http.requests{$$env->env$$ AND $$status->status:not$$}\",
              \"denominator\": \"sum:http.requests{$$env->env$$}\"
            }
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"checkout_availability\",
          \"blueprint_ref\": \"api_availability\",
          \"inputs\": { \"env\": \"production\", \"status\": true, \"threshold\": 99.95, \"window_in_days\": 30 }
        }]
      }",
        "acme/payments/slos.json",
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
        "{
        \"blueprints\": [{
          \"name\": \"simple_slo\",
          \"artifact_refs\": [\"SLO\"],
          \"params\": {},
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"numerator / denominator\",
            \"queries\": { \"numerator\": \"count:test\", \"denominator\": \"count:test\" }
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"my_slo\",
          \"blueprint_ref\": \"simple_slo\",
          \"inputs\": { \"threshold\": 99.0, \"window_in_days\": 7 }
        }]
      }",
        "myorg/myteam/myservice.json",
        ["org:myorg", "team:myteam", "service:myservice"],
      ),
      True,
    ),
    // time_slice SLO expression
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"cpu_slo\",
          \"artifact_refs\": [\"SLO\"],
          \"params\": { \"env\": \"String\" },
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"time_slice(avg:system.cpu.user{$$env->env$$} > 99.5 per 300s)\",
            \"queries\": {}
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"cpu_availability\",
          \"blueprint_ref\": \"cpu_slo\",
          \"inputs\": { \"env\": \"production\", \"threshold\": 99.9, \"window_in_days\": 30 }
        }]
      }",
        "acme/infra/slos.json",
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
    // sad path - invalid blueprint JSON
    #(
      #(
        "{ invalid json }",
        "{\"expectations\": []}",
        "playground/demo/service.json",
        [],
      ),
      False,
    ),
    // sad path - invalid expectations JSON
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"api_availability\",
          \"artifact_refs\": [\"SLO\"],
          \"params\": {},
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"1\",
            \"queries\": { \"numerator\": \"1\", \"denominator\": \"1\" }
          }
        }]
      }",
        "not valid json",
        "playground/demo/service.json",
        [],
      ),
      False,
    ),
    // sad path - missing blueprint reference
    #(
      #(
        "{\"blueprints\": []}",
        "{
        \"expectations\": [{
          \"name\": \"my_slo\",
          \"blueprint_ref\": \"nonexistent_blueprint\",
          \"inputs\": {}
        }]
      }",
        "playground/demo/service.json",
        [],
      ),
      False,
    ),
    // sad path - invalid dependency reference (target does not exist)
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"slo_with_deps\",
          \"artifact_refs\": [\"SLO\", \"DependencyRelations\"],
          \"params\": {},
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"numerator / denominator\",
            \"queries\": { \"numerator\": \"count:test\", \"denominator\": \"count:test\" },
            \"relations\": { \"hard\": [\"nonexistent.org.team.slo\"] }
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"my_slo\",
          \"blueprint_ref\": \"slo_with_deps\",
          \"inputs\": { \"threshold\": 99.0, \"window_in_days\": 7 }
        }]
      }",
        "myorg/myteam/myservice.json",
        [],
      ),
      False,
    ),
    // sad path - invalid dependency format (not 4 parts)
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"slo_with_deps\",
          \"artifact_refs\": [\"SLO\", \"DependencyRelations\"],
          \"params\": {},
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"numerator / denominator\",
            \"queries\": { \"numerator\": \"count:test\", \"denominator\": \"count:test\" },
            \"relations\": { \"hard\": [\"invalid_format\"] }
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"my_slo\",
          \"blueprint_ref\": \"slo_with_deps\",
          \"inputs\": { \"threshold\": 99.0, \"window_in_days\": 7 }
        }]
      }",
        "myorg/myteam/myservice.json",
        [],
      ),
      False,
    ),
    // sad path - self-reference in dependency
    #(
      #(
        "{
        \"blueprints\": [{
          \"name\": \"slo_with_deps\",
          \"artifact_refs\": [\"SLO\", \"DependencyRelations\"],
          \"params\": {},
          \"inputs\": {
            \"vendor\": \"datadog\",
            \"value\": \"numerator / denominator\",
            \"queries\": { \"numerator\": \"count:test\", \"denominator\": \"count:test\" },
            \"relations\": { \"hard\": [\"myorg.myteam.myservice.my_slo\"] }
          }
        }]
      }",
        "{
        \"expectations\": [{
          \"name\": \"my_slo\",
          \"blueprint_ref\": \"slo_with_deps\",
          \"inputs\": { \"threshold\": 99.0, \"window_in_days\": 7 }
        }]
      }",
        "myorg/myteam/myservice.json",
        [],
      ),
      False,
    ),
  ]
  |> test_helpers.array_based_test_executor_1(fn(input) {
    let #(blueprints_json, expectations_json, path, expected_substrings) = input
    let result =
      compiler.compile_from_strings(blueprints_json, expectations_json, path)
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
