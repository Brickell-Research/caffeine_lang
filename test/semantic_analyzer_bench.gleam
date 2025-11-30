import argv
import caffeine_lang_v2/common/ast
import caffeine_lang_v2/common/helpers
import caffeine_lang_v2/parser/artifacts
import caffeine_lang_v2/parser/blueprints
import caffeine_lang_v2/parser/expectations
import caffeine_lang_v2/semantic_analyzer
import gleam/dict
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleamy/bench
import simplifile

pub fn main() {
  let args = argv.load().arguments

  case args {
    ["--json", output_path] -> run_benchmark_json(output_path)
    _ -> run_benchmark_table()
  }
}

fn run_benchmark_table() {
  io.println("Running semantic analyzer benchmarks...")
  io.println("")

  run_benchmark()
  |> bench.table([bench.IPS, bench.Min, bench.P(99)])
  |> io.println
}

fn run_benchmark_json(output_path: String) {
  let results = run_benchmark()

  let json =
    results.sets
    |> list.map(set_to_json)
    |> string.join(",\n  ")
    |> fn(s) { "[\n  " <> s <> "\n]" }

  case simplifile.write(output_path, json) {
    Ok(_) -> io.println("Benchmark results written to " <> output_path)
    Error(_) -> io.println("Error writing to " <> output_path)
  }
}

fn set_to_json(set: bench.Set) -> String {
  let ips = calculate_ips(set.reps)
  let min = calculate_min(set.reps)
  let p99 = calculate_percentile(99, set.reps)

  "{"
  <> "\"input\": \""
  <> set.input
  <> "\", "
  <> "\"ips\": "
  <> float.to_string(ips)
  <> ", "
  <> "\"min_ms\": "
  <> float.to_string(min)
  <> ", "
  <> "\"p99_ms\": "
  <> float.to_string(p99)
  <> "}"
}

fn calculate_ips(reps: List(Float)) -> Float {
  let total = float.sum(reps)
  let count = int.to_float(list.length(reps))
  1000.0 *. count /. total
}

fn calculate_min(reps: List(Float)) -> Float {
  reps
  |> list.fold(999_999_999.0, float.min)
}

fn calculate_percentile(n: Int, reps: List(Float)) -> Float {
  let sorted = list.sort(reps, float.compare)
  let index = n * list.length(reps) / 100
  sorted
  |> list.drop(index)
  |> list.first
  |> fn(r) {
    case r {
      Ok(v) -> v
      Error(_) -> 0.0
    }
  }
}

fn run_benchmark() -> bench.BenchResults {
  // Benchmark with realistic organization sizes
  // Format: (artifacts, blueprints, expectations)
  bench.run(
    [
      bench.Input("small (1/10/50)", #(1, 10, 50)),
      bench.Input("medium (1/50/300)", #(1, 50, 300)),
      bench.Input("large (5/100/1000)", #(5, 100, 1000)),
      bench.Input("xlarge (10/200/2000)", #(10, 200, 2000)),
    ],
    [
      bench.Function("semantic_analyzer.perform", fn(config) {
        let #(num_artifacts, num_blueprints, num_expectations) = config
        let ast = build_ast(num_artifacts, num_blueprints, num_expectations)
        semantic_analyzer.perform(ast)
      }),
    ],
    [bench.Duration(3000), bench.Warmup(100)],
  )
}

fn build_ast(
  num_artifacts: Int,
  num_blueprints: Int,
  num_expectations: Int,
) -> ast.AST {

  let artifacts = list.range(1, num_artifacts) |> list.map(make_artifact)
  let blueprints =
    list.range(1, num_blueprints)
    |> list.map(fn(i) { make_blueprint(i, num_artifacts) })
  let expectations =
    list.range(1, num_expectations)
    |> list.map(fn(i) { make_expectation(i, num_blueprints) })

  ast.AST(artifacts:, blueprints:, expectations:)
}

fn make_artifact(index: Int) -> artifacts.Artifact {
  let name = "artifact_" <> int.to_string(index)
  let base_params =
    dict.from_list([
      #("threshold", helpers.Float),
      #("window_in_days", helpers.Optional(helpers.Integer)),
      #("enabled", helpers.Boolean),
    ])
  let params =
    dict.from_list([
      #("query", helpers.String),
      #("tags", helpers.NonEmptyList(helpers.String)),
    ])

  let assert Ok(artifact) =
    artifacts.make_artifact(name:, version: "1.0.0", base_params:, params:)
  artifact
}

fn make_blueprint(index: Int, num_artifacts: Int) -> blueprints.Blueprint {
  let name = "blueprint_" <> int.to_string(index)
  // Distribute blueprints across artifacts
  let artifact_index = { index - 1 } % num_artifacts + 1
  let artifact = "artifact_" <> int.to_string(artifact_index)

  let params =
    dict.from_list([
      #("environment", helpers.String),
      #("region", helpers.String),
    ])

  let inputs =
    dict.from_list([
      #("query", "\"SELECT * FROM metrics\""),
      #("tags", "[\"production\", \"critical\"]"),
    ])

  blueprints.make_blueprint(name:, artifact:, params:, inputs:)
}

fn make_expectation(index: Int, num_blueprints: Int) -> expectations.Expectation {
  let name = "expectation_" <> int.to_string(index)
  // Distribute expectations across blueprints
  let blueprint_index = { index - 1 } % num_blueprints + 1
  let blueprint = "blueprint_" <> int.to_string(blueprint_index)

  let inputs =
    dict.from_list([
      #("environment", "\"production\""),
      #("region", "\"us-east-1\""),
      #("threshold", "99.9"),
      #("window_in_days", "30"),
      #("enabled", "true"),
    ])

  expectations.make_service_expectation(name:, blueprint:, inputs:)
}
