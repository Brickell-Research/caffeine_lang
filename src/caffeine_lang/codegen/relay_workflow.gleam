/// Codegen for the GitHub Actions workflow that runs the bundled relay.
///
/// The output is a static YAML file the compiler dumps verbatim at
/// `.github/workflows/caffeine-relay.yml` whenever any expectation uses
/// external-signal indicators. The workflow:
///
///   - fires every 5 minutes (cron) and on `workflow_dispatch`
///   - uses a single-slot concurrency group so a slow run doesn't overlap
///     itself
///   - installs Erlang + Gleam via `erlef/setup-beam`
///   - restores the cursor file from GHA cache, then saves it back on exit
///     so each run picks up where the last one stopped
///   - invokes the bundled relay project via `gleam run`
///   - pulls Langfuse and Datadog credentials from repo secrets
///
/// Paths assume the layout from `codegen/relay` (Task #5) and the bundled
/// relay project from Task #7: `build/relay/signals.json` for the routing
/// table and `build/relay/relay/` for the Gleam project itself.

/// Returns `None` when no relay is needed (the compiler decides based on
/// whether any IR uses external-signal indicators). The wrapped string is
/// the literal YAML the compiler writes to disk.
pub fn generate() -> String {
  workflow_yaml
}

const workflow_yaml = "name: caffeine-relay

on:
  schedule:
    - cron: \"*/5 * * * *\"
  workflow_dispatch: {}

concurrency:
  group: caffeine-relay
  cancel-in-progress: false

jobs:
  relay:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          otp-version: \"27\"
          gleam-version: \"1.x\"

      - uses: actions/cache/restore@v4
        with:
          path: .caffeine/cursor.json
          key: caffeine-cursor-${{ github.run_id }}
          restore-keys: caffeine-cursor-

      - run: gleam run -- --config ../signals.json --cursor ../../.caffeine/cursor.json
        working-directory: build/relay/relay
        env:
          LANGFUSE_PUBLIC_KEY: ${{ secrets.LANGFUSE_PUBLIC_KEY }}
          LANGFUSE_SECRET_KEY: ${{ secrets.LANGFUSE_SECRET_KEY }}
          # Override for self-hosted / EU cloud; leave the repo var unset
          # to default to https://cloud.langfuse.com.
          LANGFUSE_BASE_URL: ${{ vars.LANGFUSE_BASE_URL }}
          DD_API_KEY: ${{ secrets.DD_API_KEY }}

      - if: always()
        uses: actions/cache/save@v4
        with:
          path: .caffeine/cursor.json
          key: caffeine-cursor-${{ github.run_id }}
"
