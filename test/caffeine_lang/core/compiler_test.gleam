import caffeine_lang/core/compilation_configuration.{CompilationConfig}
import caffeine_lang/core/compiler
import caffeine_lang/core/logger.{Minimal}
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

fn corpus_path(file_name: String) -> String {
  "test/caffeine_lang/corpus/compiler/" <> file_name
}

// ==== Main Compile Test ====
// * ✅ happy path - none
// * ✅ happy path - single
// * ✅ happy path - multiple (3 SLOs across 2 teams)
pub fn compile_test() {
  [
    // happy path - none
    #(
      corpus_path("happy_path_no_expectations_blueprints.json"),
      corpus_path("happy_path_no_expectations"),
      corpus_path("happy_path_no_expectations_output.tf"),
    ),
    // happy path - single
    #(
      corpus_path("happy_path_single_blueprints.json"),
      corpus_path("happy_path_single_expectations"),
      corpus_path("happy_path_single_output.tf"),
    ),
    // happy path - multiple (3 SLOs across 2 teams)
    #(
      corpus_path("happy_path_multiple_blueprints.json"),
      corpus_path("happy_path_multiple_expectations"),
      corpus_path("happy_path_multiple_output.tf"),
    ),
  ]
  |> list.each(fn(tuple) {
    let #(input_blueprints_path, input_expectations_dir, expected_path) = tuple
    let assert Ok(expected) = simplifile.read(expected_path)

    let config = CompilationConfig(log_level: Minimal)
    compiler.compile(input_blueprints_path, input_expectations_dir, config)
    |> should.equal(Ok(expected))
  })
}

// ==== Compile From Strings Test ====
// * ✅ happy path - single expectation with templated queries
// * ✅ happy path - path extraction (org/team/service from file path)
// * ✅ happy path - time_slice SLO expression
// * ✅ sad path   - invalid blueprint JSON
// * ✅ sad path   - invalid expectations JSON
// * ✅ sad path   - missing blueprint reference
pub fn compile_from_strings_happy_path_test() {
  // happy paths
  [
    // single expectation with templated queries
    #(
      "{
        \"blueprints\": [{
          \"name\": \"api_availability\",
          \"artifact_ref\": \"SLO\",
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
    // path extraction (org/team/service from file path)
    #(
      "{
        \"blueprints\": [{
          \"name\": \"simple_slo\",
          \"artifact_ref\": \"SLO\",
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
    // time_slice SLO expression
    #(
      "{
        \"blueprints\": [{
          \"name\": \"cpu_slo\",
          \"artifact_ref\": \"SLO\",
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
  ]
  |> list.each(fn(test_case) {
    let #(blueprints_json, expectations_json, path, expected_substrings) =
      test_case
    let result =
      compiler.compile_from_strings(blueprints_json, expectations_json, path)

    should.be_ok(result)

    let assert Ok(terraform) = result
    expected_substrings
    |> list.each(fn(substring) {
      should.be_true(string.contains(terraform, substring))
    })
  })

  // sad paths
  [
    // invalid blueprint JSON
    #(
      "{ invalid json }",
      "{\"expectations\": []}",
      "playground/demo/service.json",
    ),
    // invalid expectations JSON
    #(
      "{
        \"blueprints\": [{
          \"name\": \"api_availability\",
          \"artifact_ref\": \"SLO\",
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
    ),
    // missing blueprint reference
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
    ),
  ]
  |> list.each(fn(test_case) {
    let #(blueprints_json, expectations_json, path) = test_case

    compiler.compile_from_strings(blueprints_json, expectations_json, path)
    |> should.be_error()
  })
}
