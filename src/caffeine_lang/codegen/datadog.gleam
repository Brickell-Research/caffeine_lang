import caffeine_lang/codegen/datadog_cql
import caffeine_lang/codegen/datadog_template as templatizer
import caffeine_lang/codegen/generator_utils
import caffeine_lang/constants
import caffeine_lang/errors.{type CompilationError}
import caffeine_lang/helpers
import caffeine_lang/linker/dependency
import caffeine_lang/linker/ir.{
  type DepsValidated, type IntermediateRepresentation, type Resolved,
  IntermediateRepresentation, SloFields, ir_to_identifier,
}
import caffeine_lang/value
import datadog_query/filter
import datadog_query/lint
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set
import gleam/string
import terra_madre/common
import terra_madre/hcl
import terra_madre/terraform

/// Resolves Datadog indicator templates in an intermediate representation.
///
/// Walks `ir.values["indicators"]` (the canonical Value-typed dict the linker
/// populates) and produces a Resolved IR where both:
///   - `ir.values["indicators"]` has template variables (`$$var$$`) expanded
///   - `slo.indicators` is a fully-typed `Dict(String, IndicatorSource)` —
///     `LiteralQuery(resolved)` for string-valued entries; `ExternalSignal`
///     for the new relay-fed indicators (with match clauses also template-
///     resolved, preserving `value_extraction` from the upstream linker).
///
/// `evaluation` is also template-resolved here because it's the only other
/// templated field today.
@internal
pub fn resolve_indicators(
  ir: IntermediateRepresentation(DepsValidated),
) -> Result(IntermediateRepresentation(Resolved), CompilationError) {
  let values_index = helpers.index_value_tuples(ir.values)

  use indicators_value_tuple <- result.try(
    dict.get(values_index, "indicators")
    |> result.replace_error(errors.semantic_analysis_template_resolution_error(
      msg: "expectation '"
      <> ir_to_identifier(ir)
      <> "' - missing 'indicators' field in IR",
    )),
  )

  use raw_indicators_dict <- result.try(
    value.extract_dict(indicators_value_tuple.value)
    |> result.map_error(fn(_) {
      errors.semantic_analysis_template_resolution_error(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to decode indicators",
      )
    }),
  )

  let identifier = ir_to_identifier(ir)

  // Resolve every indicator entry to both its post-resolution Value form
  // (for `ir.values` writeback) and its typed `IndicatorSource` form (for
  // `slo.indicators`).
  use resolved_pairs <- result.try(
    raw_indicators_dict
    |> dict.to_list
    |> list.try_map(fn(pair) {
      let #(name, raw_value) = pair
      resolve_one_indicator(name, raw_value, ir, identifier)
    }),
  )

  let new_value_dict =
    resolved_pairs
    |> list.map(fn(triple) { #(triple.0, triple.1) })
    |> dict.from_list
    |> value.DictValue

  let new_indicators_value_tuple =
    helpers.ValueTuple(
      "indicators",
      indicators_value_tuple.typ,
      new_value_dict,
    )

  let resolved_indicators_dict =
    resolved_pairs
    |> list.map(fn(triple) { #(triple.0, triple.2) })
    |> dict.from_list

  // Also resolve templates in the "evaluation" field if present.
  use resolved_evaluation_tuple <- result.try(case
    dict.get(values_index, "evaluation")
  {
    Error(_) -> Ok(option.None)
    Ok(evaluation_tuple) -> {
      use evaluation_string <- result.try(
        value.extract_string(evaluation_tuple.value)
        |> result.map_error(fn(_) {
          errors.semantic_analysis_template_resolution_error(
            msg: "expectation '"
            <> ir_to_identifier(ir)
            <> "' - failed to decode 'evaluation' field as string",
          )
        }),
      )
      templatizer.parse_and_resolve_query_template(
        evaluation_string,
        ir.values,
        from: identifier,
      )
      |> result.map(fn(resolved_evaluation) {
        option.Some(helpers.ValueTuple(
          "evaluation",
          evaluation_tuple.typ,
          value.StringValue(resolved_evaluation),
        ))
      })
    }
  })

  let new_values =
    ir.values
    |> list.map(fn(vt) {
      case vt.label {
        "indicators" -> new_indicators_value_tuple
        "evaluation" ->
          case resolved_evaluation_tuple {
            option.Some(new_evaluation) -> new_evaluation
            option.None -> vt
          }
        _ -> vt
      }
    })

  let resolved_eval = case resolved_evaluation_tuple {
    option.Some(vt) -> value.extract_string(vt.value) |> option.from_result
    option.None -> ir.slo.evaluation
  }
  let new_ir =
    ir.map_slo(IntermediateRepresentation(..ir, values: new_values), fn(slo) {
      SloFields(
        ..slo,
        indicators: resolved_indicators_dict,
        evaluation: resolved_eval,
      )
    })

  Ok(ir.promote(new_ir))
}

/// Resolve a single indicator entry. Returns a triple `#(name, resolved_value,
/// indicator_source)`:
///   - `resolved_value` is the post-template-resolution Value (StringValue
///     for inline-query indicators, ExternalIndicatorValue for relay-fed)
///     for the `ir.values` writeback.
///   - `indicator_source` is the typed `IndicatorSource` for `slo.indicators`.
/// External-indicator `value_extraction` is preserved from the pre-existing
/// `ir.slo.indicators` entry (populated by the linker) — the Value layer
/// can't carry the resolved type, so we look it up here.
fn resolve_one_indicator(
  name: String,
  val: value.Value,
  ir: IntermediateRepresentation(DepsValidated),
  identifier: String,
) -> Result(
  #(String, value.Value, ir.IndicatorSource),
  CompilationError,
) {
  case val {
    value.StringValue(q) -> {
      use resolved <- result.map(templatizer.parse_and_resolve_query_template(
        q,
        ir.values,
        from: identifier,
      ))
      #(name, value.StringValue(resolved), ir.LiteralQuery(resolved))
    }
    value.ExternalIndicatorValue(source, match, value_path) -> {
      use resolved_match <- result.try(
        match
        |> dict.to_list
        |> list.try_map(fn(pair) {
          let #(field, field_val) = pair
          case field_val {
            value.StringValue(s) -> {
              use resolved <- result.map(
                templatizer.parse_and_resolve_query_template(
                  s,
                  ir.values,
                  from: identifier,
                ),
              )
              #(field, value.StringValue(resolved))
            }
            other -> Ok(#(field, other))
          }
        })
        |> result.map(dict.from_list),
      )
      // Recover the resolved type extraction from the linker-populated
      // slo.indicators; the Value layer dropped the AcceptedTypes constraint.
      let value_extraction = case dict.get(ir.slo.indicators, name) {
        Ok(ir.ExternalSignal(_, _, ve)) -> ve
        _ -> option.None
      }
      Ok(#(
        name,
        value.ExternalIndicatorValue(source, resolved_match, value_path),
        ir.ExternalSignal(
          source: source,
          match: resolved_match,
          value_extraction: value_extraction,
        ),
      ))
    }
    other ->
      Error(errors.semantic_analysis_template_resolution_error(
        msg: "expectation '"
          <> identifier
          <> "' - indicator '"
          <> name
          <> "' has unsupported value shape: "
          <> value.classify(other),
      ))
  }
}

/// Default evaluation expression used when no explicit evaluation is provided.
const default_evaluation = "numerator / denominator"

/// Synthesize a Datadog metric query string for an indicator. `LiteralQuery`
/// passes through unchanged (the user-authored query). `ExternalSignal`
/// produces a query against the synthesized metric the relay will emit to:
///   - no value extraction → count-style:
///     `sum:caffeine.<unique>{indicator:<name>}.as_count()`
///   - with value extraction → distribution-style:
///     `avg:caffeine.<unique>{indicator:<name>}`
///
/// One metric per measurement, distinguished by the `indicator:<name>` tag.
/// This is the idiomatic Datadog metric-SLO shape — every working example
/// in the provider's acceptance tests uses the same metric on both sides
/// of the ratio, sliced by tags (e.g. `{type:good}` vs `{*}`). Emitting two
/// sibling metrics like `caffeine.<unique>.good` and `caffeine.<unique>.total`
/// works in theory but doubles the chicken-and-egg problem (both metrics
/// must exist before the SLO can be created).
fn synthesize_indicator_query(
  unique_identifier: String,
  indicator_name: String,
  src: ir.IndicatorSource,
) -> String {
  case src {
    ir.LiteralQuery(q) -> q
    ir.ExternalSignal(_, _, value_extraction) -> {
      // Datadog metric names allow only `[A-Za-z0-9._]`; user-supplied
      // expectation / measurement names can carry spaces and other chars
      // that DD silently rewrites at submission time. Force the rewrite
      // at codegen time so the synthesized query, the relay emission, and
      // any DD-side stored name all agree by construction.
      let metric =
        "caffeine." <> generator_utils.dd_metric_safe(unique_identifier)
      let filter =
        "{indicator:" <> generator_utils.dd_metric_safe(indicator_name) <> "}"
      case value_extraction {
        option.None -> "sum:" <> metric <> filter <> ".as_count()"
        option.Some(_) -> "avg:" <> metric <> filter
      }
    }
  }
}

/// Generate only the Terraform resources for Datadog IRs (no config/provider).
/// Returns warnings alongside the resource list.
@internal
pub fn generate_resources(
  irs: List(IntermediateRepresentation(Resolved)),
) -> Result(#(List(terraform.Resource), List(String)), CompilationError) {
  irs
  |> list.try_fold(#([], []), fn(acc, ir) {
    let #(resources, warning_lists) = acc
    use #(resource, ir_warnings) <- result.try(ir_to_terraform_resource(ir))
    Ok(#([resource, ..resources], [ir_warnings, ..warning_lists]))
  })
  |> result.map(fn(pair) {
    #(list.reverse(pair.0), list.flatten(list.reverse(pair.1)))
  })
}

/// Convert a single IntermediateRepresentation to a Terraform Resource.
/// Uses CQL to parse the value expression and generate HCL blocks.
@internal
pub fn ir_to_terraform_resource(
  ir: IntermediateRepresentation(Resolved),
) -> Result(#(terraform.Resource, List(String)), CompilationError) {
  let resource_name = common.sanitize_terraform_identifier(ir.unique_identifier)

  let slo = ir.slo
  let threshold = slo.threshold
  let window_in_days = slo.window_in_days
  let indicators = slo.indicators
  let evaluation_expr = slo.evaluation |> option.unwrap(default_evaluation)
  let runbook = slo.runbook
  let description = slo.description

  // CQL parsing consumes resolved query strings. `LiteralQuery` indicators
  // pass through; `ExternalSignal` indicators get a query synthesized on the
  // fly that references the metric the relay emits to.
  let indicator_strings =
    indicators
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(name, src) = pair
      #(name, synthesize_indicator_query(ir.unique_identifier, name, src))
    })
    |> dict.from_list

  // Parse the evaluation expression using CQL and get HCL blocks. The
  // `below_ms` override from a `Guarantees N% below <duration>` clause flows
  // through here; it overrides the time_slice latency threshold and errors on
  // a metric SLO.
  use datadog_cql.ResolvedSloHcl(slo_type, slo_blocks) <- result.try(
    datadog_cql.resolve_slo_to_hcl(
      evaluation_expr,
      indicator_strings,
      slo.below_ms,
    )
    |> result.map_error(fn(err) {
      errors.generator_slo_query_resolution_error(
        msg: "expectation '"
        <> ir_to_identifier(ir)
        <> "' - failed to resolve SLO query: "
        <> err,
      )
    }),
  )

  // Build dependency relation tags from SloFields.depends_on.
  let dependency_tags = case slo.depends_on {
    option.Some(relations) -> build_dependency_tags(relations)
    option.None -> []
  }

  // Build user-provided tags as key-value pairs.
  let user_tag_pairs = slo.tags

  // Build system tags from IR metadata.
  let system_tag_pairs =
    helpers.build_system_tag_pairs(
      org_name: ir.metadata.org_name,
      team_name: ir.metadata.team_name,
      service_name: ir.metadata.service_name,
      measurement_name: ir.metadata.measurement_name,
      friendly_label: ir.metadata.friendly_label,
      misc: ir.metadata.misc,
    )
    |> list.append(dependency_tags)

  // Detect overshadowing: user tags whose key matches a system tag key.
  let system_tag_keys =
    system_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let user_tag_keys =
    user_tag_pairs |> list.map(fn(pair) { pair.0 }) |> set.from_list

  let overlapping_keys = set.intersection(system_tag_keys, user_tag_keys)

  // Collect warnings about overshadowing and filter out overshadowed system tags.
  let #(final_system_tag_pairs, overshadowing_warnings) = case
    set.size(overlapping_keys) > 0
  {
    True -> {
      let warn_msgs =
        overlapping_keys
        |> set.to_list
        |> list.sort(string.compare)
        |> list.map(fn(key) {
          ir_to_identifier(ir)
          <> " - user tag '"
          <> key
          <> "' overshadows system tag"
        })
      let filtered =
        system_tag_pairs
        |> list.filter(fn(pair) { !set.contains(overlapping_keys, pair.0) })
      #(filtered, warn_msgs)
    }
    False -> #(system_tag_pairs, [])
  }

  // Warn about `@`-prefixed attributes in indicator/evaluation queries.
  // Datadog rejects these because log-based metrics expose log facet `@type`
  // as the bare metric tag `type` — querying `@type:foo` 400s.
  let at_prefixed_attrs =
    indicator_strings
    |> dict.values
    |> list.append([evaluation_expr])
    |> list.flat_map(lint.at_prefixed_attrs)
    |> list.unique
  let at_prefix_warnings =
    at_prefixed_attrs
    |> list.sort(string.compare)
    |> list.map(fn(attr) {
      ir_to_identifier(ir)
      <> " - query references '"
      <> attr
      <> "' which Datadog rejects in metric SLO filters; use bare '"
      <> string.drop_start(attr, 1)
      <> "' instead (Datadog strips '@' from log-based metric attribute names)"
    })

  let warnings = list.append(overshadowing_warnings, at_prefix_warnings)

  let tags =
    list.append(final_system_tag_pairs, user_tag_pairs)
    |> list.map(fn(pair) { hcl.StringLiteral(filter.tag(pair.0, pair.1)) })
    |> hcl.ListExpr

  let identifier = ir_to_identifier(ir)

  use window_in_days_string <- result.try(
    window_to_timeframe(window_in_days)
    |> result.map_error(fn(err) { errors.prefix_error(err, identifier) }),
  )

  // Build the thresholds block (common to both types).
  let thresholds_block =
    hcl.simple_block("thresholds", [
      #("timeframe", hcl.StringLiteral(window_in_days_string)),
      #("target", hcl.FloatLiteral(threshold)),
    ])

  let type_str = case slo_type {
    datadog_cql.TimeSliceSlo -> "time_slice"
    datadog_cql.MetricSlo -> "metric"
  }

  let base_attributes = [
    #("name", hcl.StringLiteral(ir.metadata.friendly_label.value)),
    #("type", hcl.StringLiteral(type_str)),
    #("tags", tags),
  ]

  let attributes = case build_description_expr(description, runbook) {
    option.Some(desc_expr) -> [#("description", desc_expr), ..base_attributes]
    option.None -> base_attributes
  }

  Ok(#(
    terraform.Resource(
      type_: "datadog_service_level_objective",
      name: resource_name,
      attributes: dict.from_list(attributes),
      blocks: list.append(slo_blocks, [thresholds_block]),
      meta: hcl.empty_meta(),
      lifecycle: option.None,
    ),
    warnings,
  ))
}

/// Combine the SLO description (from `###` doc comments) with the runbook
/// link, if either is present. Multi-line descriptions render as an HCL
/// heredoc; single-line descriptions render as a plain string literal.
fn build_description_expr(
  description: option.Option(String),
  runbook: option.Option(String),
) -> option.Option(hcl.Expr) {
  let runbook_link = option.map(runbook, fn(url) { "[Runbook](" <> url <> ")" })
  let combined = case description, runbook_link {
    option.None, option.None -> option.None
    option.Some(d), option.None -> option.Some(d)
    option.None, option.Some(r) -> option.Some(r)
    option.Some(d), option.Some(r) -> option.Some(d <> "\n\n" <> r)
  }
  option.map(combined, description_text_to_expr)
}

fn description_text_to_expr(text: String) -> hcl.Expr {
  case string.contains(text, "\n") {
    True -> hcl.Heredoc("EOT", True, [hcl.LiteralPart(text <> "\n")])
    False -> hcl.StringLiteral(text)
  }
}

/// Build dependency relation tag pairs from the relations dict.
/// Generates pairs like #("soft_dependency", "target1,target2").
fn build_dependency_tags(
  relations: dict.Dict(dependency.DependencyRelationType, List(String)),
) -> List(#(String, String)) {
  relations
  |> dict.to_list
  |> list.sort(fn(a, b) {
    string.compare(
      dependency.relation_type_to_string(a.0),
      dependency.relation_type_to_string(b.0),
    )
  })
  |> list.map(fn(pair) {
    let #(relation_type, targets) = pair
    let sorted_targets = targets |> list.sort(string.compare)
    #(
      dependency.relation_type_to_string(relation_type) <> "_dependency",
      string.join(sorted_targets, ","),
    )
  })
}

/// Convert window_in_days to Datadog timeframe string.
/// Range (1-90) is guaranteed by the standard library; Datadog further restricts to {7, 30, 90}.
@internal
pub fn window_to_timeframe(days: Int) -> Result(String, CompilationError) {
  let days_string = int.to_string(days)
  case days {
    7 | 30 | 90 -> Ok(days_string <> "d")
    _ ->
      Error(generator_utils.resolution_error(
        vendor: constants.vendor_datadog,
        msg: "Illegal window_in_days value: "
          <> days_string
          <> ". Accepted values are 7, 30, or 90.",
      ))
  }
}
