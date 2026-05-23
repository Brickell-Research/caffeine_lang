/// Codegen for the bundled relay Gleam project.
///
/// The compiler "vends" a small standalone Gleam project — `gleam.toml` plus
/// one or more source modules — into the user's repo at `build/relay/relay/`
/// on every compile. The contents are identical for every user; only the
/// per-spec `signals.json` (from `codegen/relay`) varies. At CI time the GHA
/// workflow (from `codegen/relay_workflow`) installs Gleam, `cd`s into this
/// project, and runs it.
///
/// The files are stored here as string constants so the bundle works
/// transparently on both compile targets (Erlang CLI + JavaScript browser
/// bundle) without a filesystem dependency at compile time. If the relay
/// grows large enough that inline constants become awkward, swap in a
/// build-step that reads files from `priv/relay/` and emits this module.
///
/// Task #7 ships a stub that compiles and runs but does no real work; the
/// Langfuse + Datadog clients land in Task #8.
import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Generate the bundled relay project as a path -> contents map. Returns
/// `None` when the caller decided no relay is needed (gated alongside the
/// other relay artifacts in `compiler.gleam`). Map keys are relative to
/// the bundle root — typically the consumer writes them under
/// `build/relay/relay/<key>`.
@internal
pub fn generate() -> Option(Dict(String, String)) {
  option.Some(
    dict.from_list([
      #("gleam.toml", relay_gleam_toml),
      // Module name has to match the package name so `gleam run` (no `-m`)
      // resolves it — the GHA workflow invokes it that way.
      #("src/caffeine_relay.gleam", relay_src),
      #(".gitignore", relay_gitignore),
    ]),
  )
}

const relay_gleam_toml = "name = \"caffeine_relay\"
version = \"0.0.0\"
description = \"Auto-vended by caffeine_lang. Do not hand-edit; rerun `caffeine compile` to regenerate.\"
target = \"erlang\"

[dependencies]
gleam_stdlib = \">= 0.70.0 and < 2.0.0\"
"

const relay_src = "//// Caffeine relay — entry point.
////
//// Auto-vended by `caffeine_lang`. Do not hand-edit; rerun
//// `caffeine compile` to regenerate. Real implementation (Langfuse client,
//// Datadog submitter, cursor management) lands in Task #8; this stub just
//// confirms the bundling, install, and GHA-workflow plumbing all line up.

import gleam/io

pub fn main() -> Nil {
  io.println(
    \"caffeine relay stub — Task #8 fills this in (Langfuse pull + Datadog push)\",
  )
}
"

const relay_gitignore = "build/
"
