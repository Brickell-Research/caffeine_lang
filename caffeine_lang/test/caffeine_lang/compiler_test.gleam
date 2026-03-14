import caffeine_lang/analysis/vendor
import caffeine_lang/compiler.{type CompilationOutput}
import caffeine_lang/constants
import caffeine_lang/source_file.{
  type ExpectationSource, type SourceFile, type VendorBlueprintSource,
  SourceFile, VendorBlueprintSource,
}
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleeunit/should
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

fn read_vendor_blueprint(
  path: String,
  v: vendor.Vendor,
) -> VendorBlueprintSource {
  VendorBlueprintSource(source: read_source_file(path), vendor: v)
}

// ==== compile ====
// * ✅ happy path - none
// * ✅ happy path - single
// * ✅ happy path - multiple (3 SLOs across 2 teams)
// * ✅ happy path - type alias (E2E test with type alias in Requires)
pub fn compile_test() {
  [
    // happy path - none
    #(
      "happy path - none",
      #(
        corpus_path("happy_path_no_expectations_blueprints.caffeine"),
        corpus_path("happy_path_no_expectations"),
      ),
      Ok(read_corpus("happy_path_no_expectations_output.tf")),
    ),
    // happy path - single
    #(
      "happy path - single",
      #(
        corpus_path("happy_path_single_blueprints.caffeine"),
        corpus_path("happy_path_single_expectations"),
      ),
      Ok(read_corpus("happy_path_single_output.tf")),
    ),
    // happy path - multiple (3 SLOs across 2 teams)
    #(
      "happy path - multiple (3 SLOs across 2 teams)",
      #(
        corpus_path("happy_path_multiple_blueprints.caffeine"),
        corpus_path("happy_path_multiple_expectations"),
      ),
      Ok(read_corpus("happy_path_multiple_output.tf")),
    ),
    // happy path - type alias (E2E test with type alias in Requires)
    #(
      "happy path - type alias (E2E test with type alias in Requires)",
      #(
        corpus_path("happy_path_type_alias_blueprints.caffeine"),
        corpus_path("happy_path_type_alias_expectations"),
      ),
      Ok(read_corpus("happy_path_type_alias_output.tf")),
    ),
  ]
  |> test_helpers.table_test_1(fn(input) {
    let #(input_blueprints_path, input_expectations_dir) = input
    compiler.compile(
      [read_vendor_blueprint(input_blueprints_path, vendor.Datadog)],
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
        "Blueprints for \"SLO\"
  * \"api_availability\":
    Requires { env: String, status: Boolean }
    Provides {
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
      threshold: 99.95%,
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
        "Blueprints for \"SLO\"
  * \"simple_slo\":
    Requires {}
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" }
    }
",
        "Expectations for \"simple_slo\"
  * \"my_slo\":
    Provides {
      threshold: 99.0%,
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
        "Blueprints for \"SLO\"
  * \"cpu_slo\":
    Requires { env: String }
    Provides {
      evaluation: \"time_slice(avg:system.cpu.user{$env->env$} > 99.5 per 300s)\",
      indicators: {}
    }
",
        "Expectations for \"cpu_slo\"
  * \"cpu_availability\":
    Provides {
      env: \"production\",
      threshold: 99.9%,
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
      "sad path - invalid expectations DSL",
      #(
        "Blueprints for \"SLO\"
  * \"api_availability\":
    Requires {}
    Provides {
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
      "sad path - missing blueprint reference",
      #(
        "Blueprints for \"SLO\"
  * \"some_blueprint\":
    Requires {}
    Provides {
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
      "sad path - invalid dependency reference (target does not exist)",
      #(
        "Blueprints for \"SLO\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      depends_on: { hard: [\"nonexistent.org.team.slo\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
    Provides {
      threshold: 99.0%,
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
        "Blueprints for \"SLO\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      depends_on: { hard: [\"invalid_format\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
    Provides {
      threshold: 99.0%,
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
        "Blueprints for \"SLO\"
  * \"slo_with_deps\":
    Requires {}
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: { numerator: \"count:test\", denominator: \"count:test\" },
      depends_on: { hard: [\"myorg.myteam.myservice.my_slo\"] }
    }
",
        "Expectations for \"slo_with_deps\"
  * \"my_slo\":
    Provides {
      threshold: 99.0%,
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
      compiler.compile_from_strings(
        blueprints_src,
        expectations_src,
        path,
        vendor: "datadog",
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

// ==== compile_from_strings (Honeycomb) ====
// * ✅ happy path - single Honeycomb SLO
// * ✅ sad path   - Honeycomb with invalid window (out of 1-90 range)
pub fn compile_from_strings_honeycomb_test() {
  [
    // happy path - single Honeycomb SLO
    #(
      "happy path - single Honeycomb SLO",
      #(
        "Blueprints for \"SLO\"
  * \"honeycomb_availability\":
    Requires { env: String }
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"HEATMAP(duration_ms)\"
      }
    }
",
        "Expectations for \"honeycomb_availability\"
  * \"api_success_rate\":
    Provides {
      env: \"production\",
      threshold: 99.5%,
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
        "Blueprints for \"SLO\"
  * \"hc_blueprint\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"HEATMAP(duration_ms)\"
      }
    }
",
        "Expectations for \"hc_blueprint\"
  * \"hc_slo\":
    Provides {
      threshold: 99.5%,
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
      compiler.compile_from_strings(
        blueprints_src,
        expectations_src,
        path,
        vendor: "honeycomb",
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

// ==== compile (mixed vendors) ====
// * ✅ happy path - mixed vendors (Datadog + Honeycomb)
pub fn compile_mixed_vendors_datadog_honeycomb_test() {
  let dd_source =
    SourceFile(
      path: "blueprints/datadog.caffeine",
      content: "Blueprints for \"SLO\"
  * \"dd_blueprint\":
    Requires { env: String }
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: {
        numerator: \"sum:http.requests{$env->env$}\",
        denominator: \"sum:http.requests{$env->env$}\"
      }
    }
",
    )
  let hc_source =
    SourceFile(
      path: "blueprints/honeycomb.caffeine",
      content: "Blueprints for \"SLO\"
  * \"hc_blueprint\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"HEATMAP(duration_ms)\"
      }
    }
",
    )
  let expectations = [
    SourceFile(
      path: "acme/platform/payments.caffeine",
      content: "Expectations for \"dd_blueprint\"
  * \"dd_slo\":
    Provides {
      env: \"production\",
      threshold: 99.9%,
      window_in_days: 30
    }

Expectations for \"hc_blueprint\"
  * \"hc_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 14
    }
",
    ),
  ]

  let assert Ok(output) =
    compiler.compile(
      [
        VendorBlueprintSource(source: dd_source, vendor: vendor.Datadog),
        VendorBlueprintSource(source: hc_source, vendor: vendor.Honeycomb),
      ],
      expectations,
    )

  [
    "datadog_service_level_objective",
    "honeycombio_slo",
    "honeycombio_derived_column",
    "var.datadog_api_key",
    "var.honeycomb_api_key",
  ]
  |> list.each(fn(s) {
    output.terraform |> string.contains(s) |> should.be_true()
  })
}

// ==== compile_from_strings (New Relic) ====
// * ✅ happy path - single New Relic SLO
// * ✅ sad path   - New Relic with invalid window (not 1, 7, or 28)
pub fn compile_from_strings_newrelic_test() {
  [
    // happy path - single New Relic SLO
    #(
      "happy path - single New Relic SLO",
      #(
        "Blueprints for \"SLO\"
  * \"newrelic_availability\":
    Requires { env: String }
    Provides {
      evaluation: \"good / valid\",
      indicators: {
        good: \"Transaction WHERE appName = 'payments' AND duration < 0.1\",
        valid: \"Transaction WHERE appName = 'payments'\"
      }
    }
",
        "Expectations for \"newrelic_availability\"
  * \"api_success_rate\":
    Provides {
      env: \"production\",
      threshold: 99.5%,
      window_in_days: 7
    }
",
        "acme/platform/payments.caffeine",
        [
          "newrelic_service_level",
          "api_success_rate",
          "var.newrelic_entity_guid",
          "var.newrelic_account_id",
          "var.newrelic_api_key",
          "good_events",
          "valid_events",
          "count = 7",
        ],
      ),
      True,
    ),
    // sad path - New Relic with invalid window (not 1, 7, or 28)
    #(
      "sad path - New Relic with invalid window (not 1, 7, or 28)",
      #(
        "Blueprints for \"SLO\"
  * \"nr_blueprint\":
    Requires {}
    Provides {
      evaluation: \"good / valid\",
      indicators: {
        good: \"Transaction WHERE duration < 0.1\",
        valid: \"Transaction\"
      }
    }
",
        "Expectations for \"nr_blueprint\"
  * \"nr_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 30
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
      compiler.compile_from_strings(
        blueprints_src,
        expectations_src,
        path,
        vendor: "newrelic",
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

// ==== compile (mixed vendors: Datadog + New Relic) ====
// * ✅ happy path - mixed vendors (Datadog + New Relic)
pub fn compile_mixed_vendors_datadog_newrelic_test() {
  let dd_source =
    SourceFile(
      path: "blueprints/datadog.caffeine",
      content: "Blueprints for \"SLO\"
  * \"dd_blueprint\":
    Requires { env: String }
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: {
        numerator: \"sum:http.requests{$env->env$}\",
        denominator: \"sum:http.requests{$env->env$}\"
      }
    }
",
    )
  let nr_source =
    SourceFile(
      path: "blueprints/newrelic.caffeine",
      content: "Blueprints for \"SLO\"
  * \"nr_blueprint\":
    Requires {}
    Provides {
      evaluation: \"good / valid\",
      indicators: {
        good: \"Transaction WHERE duration < 0.1\",
        valid: \"Transaction\"
      }
    }
",
    )
  let expectations = [
    SourceFile(
      path: "acme/platform/payments.caffeine",
      content: "Expectations for \"dd_blueprint\"
  * \"dd_slo\":
    Provides {
      env: \"production\",
      threshold: 99.9%,
      window_in_days: 30
    }

Expectations for \"nr_blueprint\"
  * \"nr_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 7
    }
",
    ),
  ]

  let assert Ok(output) =
    compiler.compile(
      [
        VendorBlueprintSource(source: dd_source, vendor: vendor.Datadog),
        VendorBlueprintSource(source: nr_source, vendor: vendor.NewRelic),
      ],
      expectations,
    )

  [
    "datadog_service_level_objective",
    "newrelic_service_level",
    "var.datadog_api_key",
    "var.newrelic_api_key",
  ]
  |> list.each(fn(s) {
    output.terraform |> string.contains(s) |> should.be_true()
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
        "Blueprints for \"SLO\"
  * \"dynatrace_availability\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"builtin:service.requestCount.server:splitBy()\"
      }
    }
",
        "Expectations for \"dynatrace_availability\"
  * \"api_success_rate\":
    Provides {
      threshold: 99.5%,
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
        "Blueprints for \"SLO\"
  * \"dt_blueprint\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"builtin:service.requestCount.server:splitBy()\"
      }
    }
",
        "Expectations for \"dt_blueprint\"
  * \"dt_slo\":
    Provides {
      threshold: 99.5%,
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
      compiler.compile_from_strings(
        blueprints_src,
        expectations_src,
        path,
        vendor: "dynatrace",
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

// ==== compile (mixed vendors: Datadog + Dynatrace) ====
// * ✅ happy path - mixed vendors (Datadog + Dynatrace)
pub fn compile_mixed_vendors_datadog_dynatrace_test() {
  let dd_source =
    SourceFile(
      path: "blueprints/datadog.caffeine",
      content: "Blueprints for \"SLO\"
  * \"dd_blueprint\":
    Requires { env: String }
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: {
        numerator: \"sum:http.requests{$env->env$}\",
        denominator: \"sum:http.requests{$env->env$}\"
      }
    }
",
    )
  let dt_source =
    SourceFile(
      path: "blueprints/dynatrace.caffeine",
      content: "Blueprints for \"SLO\"
  * \"dt_blueprint\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: {
        sli: \"builtin:service.requestCount.server:splitBy()\"
      }
    }
",
    )
  let expectations = [
    SourceFile(
      path: "acme/platform/payments.caffeine",
      content: "Expectations for \"dd_blueprint\"
  * \"dd_slo\":
    Provides {
      env: \"production\",
      threshold: 99.9%,
      window_in_days: 30
    }

Expectations for \"dt_blueprint\"
  * \"dt_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 14
    }
",
    ),
  ]

  let assert Ok(output) =
    compiler.compile(
      [
        VendorBlueprintSource(source: dd_source, vendor: vendor.Datadog),
        VendorBlueprintSource(source: dt_source, vendor: vendor.Dynatrace),
      ],
      expectations,
    )

  [
    "datadog_service_level_objective",
    "dynatrace_slo_v2",
    "var.datadog_api_key",
    "var.dynatrace_api_token",
  ]
  |> list.each(fn(s) {
    output.terraform |> string.contains(s) |> should.be_true()
  })
}

// ==== compile_from_strings (dependency graph) ====
// * ✅ SLO without DependencyRelations produces dependency_graph == None
// * ✅ SLO with DependencyRelations produces dependency_graph == Some(Mermaid)
pub fn compile_from_strings_dependency_graph_none_test() {
  let assert Ok(output) =
    compiler.compile_from_strings(
      "Blueprints for \"SLO\"
  * \"simple\":
    Requires {}
    Provides {
      evaluation: \"good / total\",
      indicators: { good: \"count:ok\", total: \"count:all\" }
    }
",
      "Expectations for \"simple\"
  * \"my_slo\":
    Provides {
      threshold: 99.0%,
      window_in_days: 30
    }
",
      "acme/platform/payments.caffeine",
      vendor: "datadog",
    )

  output.dependency_graph |> should.equal(option.None)
}

pub fn compile_from_strings_dependency_graph_some_test() {
  let assert Ok(output) =
    compiler.compile_from_strings(
      "Blueprints for \"SLO\"
  * \"tracked\":
    Requires {}
    Provides {
      evaluation: \"good / total\",
      indicators: { good: \"count:ok\", total: \"count:all\" },
      depends_on: { hard: [\"acme.platform.payments.standalone_slo\"], soft: [] }
    }

Blueprints for \"SLO\"
  * \"standalone\":
    Requires {}
    Provides {
      evaluation: \"good / total\",
      indicators: { good: \"count:ok\", total: \"count:all\" }
    }
",
      "Expectations for \"tracked\"
  * \"tracked_slo\":
    Provides {
      threshold: 99.0%,
      window_in_days: 30
    }

Expectations for \"standalone\"
  * \"standalone_slo\":
    Provides {
      threshold: 99.9%,
      window_in_days: 30
    }
",
      "acme/platform/payments.caffeine",
      vendor: "datadog",
    )

  // Has DependencyRelations -> graph should be Some with Mermaid content
  output.dependency_graph |> should.be_some()
  let assert option.Some(graph) = output.dependency_graph
  graph |> string.contains("graph TD") |> should.be_true()
  graph |> string.contains("tracked_slo") |> should.be_true()
  graph |> string.contains("standalone_slo") |> should.be_true()
  graph |> string.contains("-->|hard|") |> should.be_true()
}

// ==== compile (all four vendors) ====
// * ✅ all four vendors in single compilation merge providers and variables
pub fn compile_all_four_vendors_test() {
  let dd_source =
    VendorBlueprintSource(
      source: SourceFile(
        path: "blueprints/datadog.caffeine",
        content: "Blueprints for \"SLO\"
  * \"dd\":
    Requires { env: String }
    Provides {
      evaluation: \"numerator / denominator\",
      indicators: {
        numerator: \"sum:http.ok{$env->env$}\",
        denominator: \"sum:http.total{$env->env$}\"
      }
    }
",
      ),
      vendor: vendor.Datadog,
    )
  let hc_source =
    VendorBlueprintSource(
      source: SourceFile(
        path: "blueprints/honeycomb.caffeine",
        content: "Blueprints for \"SLO\"
  * \"hc\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: { sli: \"HEATMAP(duration_ms)\" }
    }
",
      ),
      vendor: vendor.Honeycomb,
    )
  let dt_source =
    VendorBlueprintSource(
      source: SourceFile(
        path: "blueprints/dynatrace.caffeine",
        content: "Blueprints for \"SLO\"
  * \"dt\":
    Requires {}
    Provides {
      evaluation: \"sli\",
      indicators: { sli: \"builtin:service.requestCount.server:splitBy()\" }
    }
",
      ),
      vendor: vendor.Dynatrace,
    )
  let nr_source =
    VendorBlueprintSource(
      source: SourceFile(
        path: "blueprints/newrelic.caffeine",
        content: "Blueprints for \"SLO\"
  * \"nr\":
    Requires {}
    Provides {
      evaluation: \"good / valid\",
      indicators: {
        good: \"Transaction WHERE duration < 0.1\",
        valid: \"Transaction\"
      }
    }
",
      ),
      vendor: vendor.NewRelic,
    )

  let expectations = [
    SourceFile(
      path: "acme/platform/payments.caffeine",
      content: "Expectations for \"dd\"
  * \"dd_slo\":
    Provides {
      env: \"production\",
      threshold: 99.9%,
      window_in_days: 30
    }

Expectations for \"hc\"
  * \"hc_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 14
    }

Expectations for \"dt\"
  * \"dt_slo\":
    Provides {
      threshold: 99.5%,
      window_in_days: 30
    }

Expectations for \"nr\"
  * \"nr_slo\":
    Provides {
      threshold: 99.0%,
      window_in_days: 7
    }
",
    ),
  ]

  let assert Ok(output) =
    compiler.compile([dd_source, hc_source, dt_source, nr_source], expectations)

  // All four vendor resources present
  output.terraform
  |> string.contains("datadog_service_level_objective")
  |> should.be_true()
  output.terraform |> string.contains("honeycombio_slo") |> should.be_true()
  output.terraform |> string.contains("dynatrace_slo_v2") |> should.be_true()
  output.terraform
  |> string.contains("newrelic_service_level")
  |> should.be_true()

  // All four providers present
  output.terraform
  |> string.contains("var.datadog_api_key")
  |> should.be_true()
  output.terraform
  |> string.contains("var.honeycomb_api_key")
  |> should.be_true()
  output.terraform
  |> string.contains("var.dynatrace_api_token")
  |> should.be_true()
  output.terraform
  |> string.contains("var.newrelic_api_key")
  |> should.be_true()

  // No deps -> graph is None
  output.dependency_graph |> should.equal(option.None)
}
