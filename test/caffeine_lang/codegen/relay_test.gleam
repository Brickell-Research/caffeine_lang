import caffeine_lang/codegen/relay.{
  type RelayFile, Boolean, LangfuseDatadogRelay, Numeric, Scorer,
}
import gleam/list
import gleeunit/should
import simplifile

const fixture_dir = "test/caffeine_lang/corpus/generator/relay/langfuse_to_datadog/"

fn fixture(name: String) -> String {
  let assert Ok(content) = simplifile.read(fixture_dir <> name)
  content
}

fn find(files: List(RelayFile), path: String) -> RelayFile {
  let assert Ok(file) = list.find(files, fn(f) { f.path == path })
  file
}

// ==== generate_langfuse_to_datadog ====
// * ✅ emits the four expected files
// * ✅ workflow YAML matches the golden fixture
// * ✅ runner gleam.toml matches the golden fixture
// * ✅ runner source matches the golden fixture
// * ✅ manifest module matches the golden fixture
pub fn langfuse_to_datadog_matches_fixtures_test() {
  let files =
    relay.generate_langfuse_to_datadog(LangfuseDatadogRelay(
      name: "langfuse_to_datadog",
      metric_prefix: "langfuse.scores",
      schedule_cron: "*/15 * * * *",
      scorers: [
        Scorer(name: "helpfulness", data_type: Numeric),
        Scorer(name: "safe", data_type: Boolean),
      ],
    ))

  files |> list.length |> should.equal(4)

  find(files, ".github/workflows/langfuse_to_datadog.yml").content
  |> should.equal(fixture("workflow.yml"))

  find(files, "relay/gleam.toml").content
  |> should.equal(fixture("gleam.toml"))

  find(files, "relay/src/relay.gleam").content
  |> should.equal(fixture("relay.gleam.txt"))

  find(files, "relay/src/manifest.gleam").content
  |> should.equal(fixture("manifest.gleam.txt"))
}
