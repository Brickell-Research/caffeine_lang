import argv
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type BenchResult {
  BenchResult(input: String, ips: Float, min_ms: Float, p99_ms: Float)
}

pub fn main() {
  let args = argv.load().arguments

  case args {
    [baseline_path, current_path] -> compare(baseline_path, current_path, 20.0)
    [baseline_path, current_path, threshold] -> {
      case float.parse(threshold) {
        Ok(t) -> compare(baseline_path, current_path, t)
        Error(_) -> {
          io.println("Error: threshold must be a number")
          exit(1)
        }
      }
    }
    _ -> {
      io.println(
        "Usage: gleam run -m benchmark_compare <baseline.json> <current.json> [threshold%]",
      )
      io.println("  threshold: maximum allowed IPS regression percentage (default: 20)")
      exit(1)
    }
  }
}

fn compare(baseline_path: String, current_path: String, threshold: Float) {
  let baseline_results = case parse_json_file(baseline_path) {
    Ok(r) -> r
    Error(e) -> {
      io.println("Error reading baseline: " <> e)
      exit(1)
    }
  }

  let current_results = case parse_json_file(current_path) {
    Ok(r) -> r
    Error(e) -> {
      io.println("Error reading current: " <> e)
      exit(1)
    }
  }

  io.println("Benchmark Comparison (threshold: " <> float.to_string(threshold) <> "%)")
  io.println("=" |> string.repeat(70))
  io.println("")

  let regressions =
    baseline_results
    |> list.filter_map(fn(baseline) {
      case list.find(current_results, fn(c) { c.input == baseline.input }) {
        Ok(current) -> {
          let ips_change = { current.ips -. baseline.ips } /. baseline.ips *. 100.0
          let regression = ips_change <. float.negate(threshold)

          let status = case regression {
            True -> "REGRESSION"
            False ->
              case ips_change >. 0.0 {
                True -> "improved"
                False -> "ok"
              }
          }

          io.println(baseline.input <> ":")
          io.println(
            "  Baseline IPS: "
            <> float.to_string(float.floor(baseline.ips))
            <> " -> Current IPS: "
            <> float.to_string(float.floor(current.ips))
            <> " ("
            <> format_change(ips_change)
            <> ") ["
            <> status
            <> "]",
          )
          io.println("")

          case regression {
            True -> Ok(baseline.input)
            False -> Error(Nil)
          }
        }
        Error(_) -> {
          io.println(baseline.input <> ": MISSING in current results")
          io.println("")
          Error(Nil)
        }
      }
    })

  case list.length(regressions) {
    0 -> {
      io.println("All benchmarks passed!")
      exit(0)
    }
    n -> {
      io.println(
        "FAILED: "
        <> int.to_string(n)
        <> " benchmark(s) regressed beyond "
        <> float.to_string(threshold)
        <> "% threshold",
      )
      exit(1)
    }
  }
}

fn format_change(change: Float) -> String {
  let sign = case change >. 0.0 {
    True -> "+"
    False -> ""
  }
  sign <> float.to_string(float.floor(change *. 10.0) /. 10.0) <> "%"
}

fn parse_json_file(path: String) -> Result(List(BenchResult), String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "Could not read file: " <> path }),
  )

  parse_json_array(content)
}

fn parse_json_array(content: String) -> Result(List(BenchResult), String) {
  // Simple JSON array parser for our specific format
  let trimmed =
    content
    |> string.trim
    |> string.drop_start(1)
    // Remove opening [
    |> string.drop_end(1)
  // Remove closing ]

  trimmed
  |> string.split("},")
  |> list.map(fn(s) {
    s
    |> string.trim
    |> fn(s2) {
      case string.ends_with(s2, "}") {
        True -> s2
        False -> s2 <> "}"
      }
    }
  })
  |> list.filter(fn(s) { s != "" && s != "}" })
  |> list.try_map(parse_json_object)
}

fn parse_json_object(obj: String) -> Result(BenchResult, String) {
  // Extract values from JSON object like:
  // {"input": "small (1/10/50)", "ips": 1309.92, "min_ms": 0.67, "p99_ms": 0.98}

  use input <- result.try(extract_string_value(obj, "input"))
  use ips <- result.try(extract_float_value(obj, "ips"))
  use min_ms <- result.try(extract_float_value(obj, "min_ms"))
  use p99_ms <- result.try(extract_float_value(obj, "p99_ms"))

  Ok(BenchResult(input:, ips:, min_ms:, p99_ms:))
}

fn extract_string_value(obj: String, key: String) -> Result(String, String) {
  let search = "\"" <> key <> "\": \""
  case string.split(obj, search) {
    [_, rest] -> {
      case string.split(rest, "\"") {
        [value, ..] -> Ok(value)
        _ -> Error("Could not parse string value for " <> key)
      }
    }
    _ -> Error("Key not found: " <> key)
  }
}

fn extract_float_value(obj: String, key: String) -> Result(Float, String) {
  let search = "\"" <> key <> "\": "
  case string.split(obj, search) {
    [_, rest] -> {
      let value_str =
        rest
        |> string.split(",")
        |> list.first
        |> result.unwrap("")
        |> string.split("}")
        |> list.first
        |> result.unwrap("")
        |> string.trim

      float.parse(value_str)
      |> result.map_error(fn(_) { "Could not parse float for " <> key })
    }
    _ -> Error("Key not found: " <> key)
  }
}

@external(erlang, "erlang", "halt")
fn exit(code: Int) -> a
