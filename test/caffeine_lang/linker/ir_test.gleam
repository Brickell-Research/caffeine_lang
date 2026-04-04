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
  promoted.values |> should.equal(linked_ir.values)
  promoted.slo |> should.equal(linked_ir.slo)
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

// ==== map_slo ====
// * ✅ applies transformation to SLO fields
pub fn map_slo_test() {
  let test_ir =
    ir_test_helpers.make_slo_ir(
      "acme",
      "platform",
      "payments",
      "api_slo",
      threshold: 99.0,
    )

  // Applies transformation
  let updated =
    ir.map_slo(test_ir, fn(s) {
      ir.SloFields(..s, threshold: 99.9, tags: [#("env", "prod")])
    })
  updated.slo.threshold |> should.equal(99.9)
  updated.slo.tags |> should.equal([#("env", "prod")])
  updated.slo.window_in_days |> should.equal(30)
}

// ==== SloFields with depends_on ====
// * ✅ SloFields stores dependency relations
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

  let assert option.Some(relations) = slo.depends_on
  dict.get(relations, Hard) |> should.equal(Ok(["a.b.c.d"]))
  dict.get(relations, Soft) |> should.equal(Ok(["e.f.g.h"]))
}
