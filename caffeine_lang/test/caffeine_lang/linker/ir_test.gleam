import caffeine_lang/linker/artifacts.{Hard, Soft}
import caffeine_lang/linker/ir
import gleam/dict
import gleam/option
import gleeunit/should
import ir_test_helpers

// ==== promote ====
// * ✅ all fields preserved across phantom type change
pub fn promote_test() {
  let linked_ir =
    ir_test_helpers.make_ir_with_deps(
      "acme",
      "platform",
      "payments",
      "api_slo",
      hard_deps: ["acme.platform.db.db_slo"],
      soft_deps: [],
      threshold: 99.9,
    )

  let promoted: ir.IntermediateRepresentation(ir.Resolved) =
    ir.promote(linked_ir)

  promoted.metadata |> should.equal(linked_ir.metadata)
  promoted.unique_identifier |> should.equal(linked_ir.unique_identifier)
  promoted.artifact_refs |> should.equal(linked_ir.artifact_refs)
  promoted.values |> should.equal(linked_ir.values)
  promoted.artifact_data |> should.equal(linked_ir.artifact_data)
  promoted.vendor |> should.equal(linked_ir.vendor)
}

// ==== ir_to_identifier ====
// * ✅ builds "org.team.service.name" dotted path
pub fn ir_to_identifier_test() {
  let ir =
    ir_test_helpers.make_slo_ir(
      "acme",
      "platform",
      "payments",
      "api_slo",
      threshold: 99.0,
    )

  ir.ir_to_identifier(ir)
  |> should.equal("acme.platform.payments.api_slo")
}

// ==== get_slo_fields ====
// * ✅ returns Some when SLO present
// * ✅ returns None when SLO absent
pub fn get_slo_fields_test() {
  let slo =
    ir.SloFields(
      threshold: 99.5,
      indicators: dict.new(),
      window_in_days: 7,
      evaluation: option.None,
      tags: [],
      runbook: option.None,
      depends_on: option.None,
    )

  ir.get_slo_fields(ir.slo_only(slo))
  |> should.equal(option.Some(slo))

  let empty_data = ir.ArtifactData(fields: dict.new())
  ir.get_slo_fields(empty_data)
  |> should.equal(option.None)
}

// ==== slo_only ====
// * ✅ creates ArtifactData with only SLO
pub fn slo_only_test() {
  let slo =
    ir.SloFields(
      threshold: 99.9,
      indicators: dict.from_list([#("numerator", "count:test")]),
      window_in_days: 30,
      evaluation: option.Some("numerator / denominator"),
      tags: [#("team", "platform")],
      runbook: option.Some("https://example.com"),
      depends_on: option.None,
    )
  let data = ir.slo_only(slo)

  ir.get_slo_fields(data) |> should.equal(option.Some(slo))
}

// ==== slo_only with depends_on ====
// * ✅ creates ArtifactData with SLO and dependency relations
pub fn slo_with_depends_on_test() {
  let slo =
    ir.SloFields(
      threshold: 99.0,
      indicators: dict.new(),
      window_in_days: 7,
      evaluation: option.None,
      tags: [],
      runbook: option.None,
      depends_on: option.Some(
        dict.from_list([
          #(Hard, ["a.b.c.d"]),
          #(Soft, ["e.f.g.h"]),
        ]),
      ),
    )
  let data = ir.slo_only(slo)

  ir.get_slo_fields(data) |> should.equal(option.Some(slo))
  let assert option.Some(retrieved) = ir.get_slo_fields(data)
  let assert option.Some(relations) = retrieved.depends_on
  dict.get(relations, Hard) |> should.equal(Ok(["a.b.c.d"]))
  dict.get(relations, Soft) |> should.equal(Ok(["e.f.g.h"]))
}

// ==== update_slo_fields ====
// * ✅ applies transformation to SLO fields
// * ✅ no-op when no SLO present
pub fn update_slo_fields_test() {
  let slo =
    ir.SloFields(
      threshold: 99.0,
      indicators: dict.new(),
      window_in_days: 30,
      evaluation: option.None,
      tags: [],
      runbook: option.None,
      depends_on: option.None,
    )
  let data = ir.slo_only(slo)

  // Applies transformation
  let updated =
    ir.update_slo_fields(data, fn(s) {
      ir.SloFields(..s, threshold: 99.9, tags: [#("env", "prod")])
    })
  let assert option.Some(updated_slo) = ir.get_slo_fields(updated)
  updated_slo.threshold |> should.equal(99.9)
  updated_slo.tags |> should.equal([#("env", "prod")])
  updated_slo.window_in_days |> should.equal(30)

  // No-op when no SLO present
  let empty_data = ir.ArtifactData(fields: dict.new())
  let unchanged =
    ir.update_slo_fields(empty_data, fn(s) {
      ir.SloFields(..s, threshold: 0.0)
    })
  ir.get_slo_fields(unchanged) |> should.equal(option.None)
}
