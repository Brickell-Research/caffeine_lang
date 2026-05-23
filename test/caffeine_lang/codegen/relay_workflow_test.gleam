import caffeine_lang/codegen/relay_workflow
import gleam/string
import gleeunit/should

// ==== generate ====
// The workflow is a static template today. These tests assert the key
// shape invariants the relay's runtime contract depends on so a future
// codegen refactor can't silently drop them.

// * ✅ workflow name and cron schedule are emitted
pub fn generate_has_name_and_schedule_test() {
  let yaml = relay_workflow.generate()
  yaml |> string.contains("name: caffeine-relay") |> should.be_true
  yaml |> string.contains("cron: \"*/5 * * * *\"") |> should.be_true
  yaml |> string.contains("workflow_dispatch") |> should.be_true
}

// * ✅ single-slot concurrency group prevents overlapping runs
pub fn generate_has_concurrency_group_test() {
  let yaml = relay_workflow.generate()
  yaml |> string.contains("group: caffeine-relay") |> should.be_true
  yaml |> string.contains("cancel-in-progress: false") |> should.be_true
}

// * ✅ erlef/setup-beam installs OTP + Gleam (relay is Gleam-on-Erlang)
pub fn generate_installs_beam_test() {
  let yaml = relay_workflow.generate()
  yaml |> string.contains("erlef/setup-beam@v1") |> should.be_true
  yaml |> string.contains("otp-version") |> should.be_true
  yaml |> string.contains("gleam-version") |> should.be_true
}

// * ✅ cursor cache restore and save are both present; save runs always
pub fn generate_cursor_cache_round_trip_test() {
  let yaml = relay_workflow.generate()
  yaml |> string.contains("actions/cache/restore@v4") |> should.be_true
  yaml |> string.contains("actions/cache/save@v4") |> should.be_true
  yaml |> string.contains("if: always()") |> should.be_true
  // The cache key uses the run id; restore-keys falls back to any prior
  // cached cursor so a missed save doesn't break the cursor lineage.
  yaml |> string.contains("key: caffeine-cursor-") |> should.be_true
  yaml |> string.contains("restore-keys: caffeine-cursor-") |> should.be_true
}

// * ✅ relay is invoked via `gleam run` from the bundled project directory
pub fn generate_invokes_relay_test() {
  let yaml = relay_workflow.generate()
  yaml |> string.contains("gleam run") |> should.be_true
  yaml |> string.contains("working-directory: build/relay/relay") |> should.be_true
  yaml |> string.contains("--config ../signals.json") |> should.be_true
}

// * ✅ all three runtime secrets are passed through as env vars
pub fn generate_passes_secrets_test() {
  let yaml = relay_workflow.generate()
  yaml
  |> string.contains("LANGFUSE_PUBLIC_KEY: ${{ secrets.LANGFUSE_PUBLIC_KEY }}")
  |> should.be_true
  yaml
  |> string.contains("LANGFUSE_SECRET_KEY: ${{ secrets.LANGFUSE_SECRET_KEY }}")
  |> should.be_true
  yaml
  |> string.contains("DD_API_KEY: ${{ secrets.DD_API_KEY }}")
  |> should.be_true
}
