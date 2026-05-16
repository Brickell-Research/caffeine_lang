/// Frontend lowering for Caffeine AST.
/// Converts validated AST to Measurement and Expectation types for the compiler pipeline.
import caffeine_lang/frontend/ast.{
  type Comment, type ExpectItem, type ExpectsFile, type Extendable, type Field,
  type Literal, type MeasurementItem, type MeasurementsFile, type Struct,
  type TypeAlias, type Validated,
}
import caffeine_lang/linker/expectations.{type Expectation, Expectation}
import caffeine_lang/linker/measurements.{
  type Measurement, type Raw, Measurement,
}
import caffeine_lang/types.{
  type AcceptedTypes, type ParsedType, CollectionType, Defaulted, Dict,
  InclusiveRange, List, ModifierType, OneOf, Optional, ParsedCollection,
  ParsedModifier, ParsedPrimitive, ParsedRecord, ParsedRefinement,
  ParsedTypeAliasRef, PrimitiveType, RecordType, RefinementType,
}
import caffeine_lang/value
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/option
import gleam/string

/// Lowers measurements from a validated measurements AST.
@internal
pub fn lower_measurements(
  file: MeasurementsFile(Validated),
) -> List(Measurement(Raw)) {
  let type_aliases = build_type_alias_map(file.type_aliases)
  let extendables = build_extendable_map(file.extendables)

  file.items
  |> list.map(fn(item) {
    generate_measurement_item(item, extendables, type_aliases)
  })
}

/// Lowers expectations from a validated expects AST.
@internal
pub fn lower_expectations(file: ExpectsFile(Validated)) -> List(Expectation) {
  let extendables = build_extendable_map(file.extendables)

  file.items
  |> list.map(fn(item) { generate_expect_item(item, extendables) })
}

/// Builds a map of extendable name to extendable for quick lookup.
fn build_extendable_map(
  extendables: List(Extendable),
) -> Dict(String, Extendable) {
  extendables
  |> list.map(fn(e) { #(e.name, e) })
  |> dict.from_list
}

/// Builds a map of type alias name to its parsed type for quick lookup.
fn build_type_alias_map(
  type_aliases: List(TypeAlias),
) -> Dict(String, ParsedType) {
  ast.build_type_alias_pairs(type_aliases)
  |> dict.from_list
}

/// Generates a single measurement from an AST item.
fn generate_measurement_item(
  item: MeasurementItem,
  extendables: Dict(String, Extendable),
  type_aliases: Dict(String, ParsedType),
) -> Measurement(Raw) {
  let #(merged_requires, merged_provides) =
    merge_measurement_extends(item, extendables)

  let params = struct_to_params(merged_requires, type_aliases)
  let inputs = struct_to_inputs(merged_provides)

  Measurement(
    name: item.name,
    params: params,
    inputs: inputs,
    expectation_type: item.expectation_type,
  )
}

/// Generates a single expectation from a new-envelope AST item.
///
/// Flattens the structured envelope (Assumes section, Guarantees clause,
/// optional `as measured by ... with: {...}`) into the flat `inputs` dict the
/// linker IR builder expects. Keys produced:
///   - "threshold": PercentageValue from `Guarantees N%`
///   - "window_in_days": IntValue from `over <dur> window` (any unit normalized to days)
///   - "depends_on": DictValue with "hard"/"soft" -> ListValue(StringValue) from `Assumes:`
///   - <each `with:` field>: literal value (after extendable merge)
fn generate_expect_item(
  item: ExpectItem,
  extendables: Dict(String, Extendable),
) -> Expectation {
  let with_args = merge_expect_with_args(item, extendables)
  let base_inputs = struct_to_inputs(with_args)

  let inputs =
    base_inputs
    |> dict.insert(
      "threshold",
      value.PercentageValue(item.guarantees.threshold),
    )
    |> dict.insert(
      "window_in_days",
      value.IntValue(duration_to_days(item.guarantees.window)),
    )
    |> maybe_insert_below_ms(item.guarantees.below)
    |> maybe_insert_depends_on(item.assumes)

  let measurement_ref = case item.guarantees.measured_by {
    option.Some(mb) -> option.Some(mb.measurement)
    option.None -> option.None
  }

  let description = extract_doc_description(item.leading_comments)

  Expectation(
    name: item.name,
    measurement_ref: measurement_ref,
    inputs: inputs,
    description: description,
  )
}

/// Converts a duration literal to whole days. Non-day units are normalized
/// through `value.duration_to_milliseconds` and divided down. Floors fractional
/// days (e.g. `1h` -> 0 days, `25h` -> 1 day) since the IR currently carries
/// `window_in_days` as an integer. Negative values clamp to 0.
fn duration_to_days(d: ast.DurationLiteral) -> Int {
  case value.duration_unit_from_string(d.unit) {
    Ok(unit) -> {
      let ms = value.duration_to_milliseconds(d.amount, unit)
      let days_float = ms /. 86_400_000.0
      case days_float <. 0.0 {
        True -> 0
        False -> float_floor_to_int(days_float)
      }
    }
    // Tokenizer only emits known suffixes, so this branch is unreachable.
    Error(Nil) -> 0
  }
}

fn float_floor_to_int(f: Float) -> Int {
  let rounded = float.round(f -. 0.5)
  case rounded < 0 {
    True -> 0
    False -> rounded
  }
}

fn maybe_insert_below_ms(
  inputs: Dict(String, value.Value),
  below: option.Option(ast.DurationLiteral),
) -> Dict(String, value.Value) {
  case below {
    option.None -> inputs
    option.Some(d) ->
      case value.duration_unit_from_string(d.unit) {
        Ok(unit) ->
          dict.insert(
            inputs,
            "below_ms",
            value.FloatValue(value.duration_to_milliseconds(d.amount, unit)),
          )
        // Unreachable — tokenizer only emits known suffixes.
        Error(Nil) -> inputs
      }
  }
}

fn maybe_insert_depends_on(
  inputs: Dict(String, value.Value),
  assumes: option.Option(ast.Assumes),
) -> Dict(String, value.Value) {
  case assumes {
    option.None -> inputs
    option.Some(a) ->
      case a.deps {
        [] -> inputs
        _ -> dict.insert(inputs, "depends_on", deps_to_value(a.deps))
      }
  }
}

fn deps_to_value(deps: List(ast.Dependency)) -> value.Value {
  let #(hard, soft) =
    list.partition(deps, fn(d) {
      case d.kind {
        ast.HardDep -> True
        ast.SoftDep -> False
      }
    })
  let hard_list =
    hard
    |> list.map(fn(d) { value.StringValue(d.target) })
    |> value.ListValue
  let soft_list =
    soft
    |> list.map(fn(d) { value.StringValue(d.target) })
    |> value.ListValue
  dict.new()
  |> dict.insert("hard", hard_list)
  |> dict.insert("soft", soft_list)
  |> value.DictValue
}

/// Extracts `###` doc-comment text from a node's leading comments and joins
/// the lines with `\n`. Returns `None` when no doc comments are present.
/// Each line drops a single leading space (the universal `### ` form) and
/// rstrips trailing whitespace. `#` and `##` comments are ignored — they're
/// treated as section headers / inline notes, not SLO descriptions.
fn extract_doc_description(comments: List(Comment)) -> option.Option(String) {
  let lines =
    comments
    |> list.filter_map(fn(c) {
      case c {
        ast.DocComment(text) -> Ok(strip_doc_comment_text(text))
        _ -> Error(Nil)
      }
    })
  case lines {
    [] -> option.None
    _ -> option.Some(string.join(lines, "\n"))
  }
}

fn strip_doc_comment_text(text: String) -> String {
  let stripped = case string.starts_with(text, " ") {
    True -> string.drop_start(text, 1)
    False -> text
  }
  string.trim_end(stripped)
}

/// Collects fields from extended extendables matching a given kind.
fn collect_extended_fields(
  extends: List(String),
  extendables: Dict(String, Extendable),
  kind: ast.ExtendableKind,
) -> List(Field) {
  extends
  |> list.flat_map(fn(name) {
    case dict.get(extendables, name) {
      Ok(ext) if ext.kind == kind -> ext.body.fields
      _ -> []
    }
  })
}

/// Merges extended fields into a measurement item's requires and provides.
/// Order: extended extendables left-to-right, then item's own fields (can override).
fn merge_measurement_extends(
  item: MeasurementItem,
  extendables: Dict(String, Extendable),
) -> #(Struct, Struct) {
  let requires_fields =
    collect_extended_fields(item.extends, extendables, ast.ExtendableRequires)
    |> list.append(item.requires.fields)
    |> dedupe_fields

  let provides_fields =
    collect_extended_fields(item.extends, extendables, ast.ExtendableProvides)
    |> list.append(item.provides.fields)
    |> dedupe_fields

  #(
    ast.Struct(requires_fields, trailing_comments: []),
    ast.Struct(provides_fields, trailing_comments: []),
  )
}

/// Merges extended fields into an expect item's `with: {...}` args.
/// Order: extended extendables left-to-right, then the item's own with-fields
/// (can override). Unmeasured expectations have no `with:`; for them only the
/// extendable fields contribute.
fn merge_expect_with_args(
  item: ExpectItem,
  extendables: Dict(String, Extendable),
) -> Struct {
  let item_fields = case item.guarantees.measured_by {
    option.Some(mb) -> mb.with_args.fields
    option.None -> []
  }
  let merged =
    collect_extended_fields(item.extends, extendables, ast.ExtendableProvides)
    |> list.append(item_fields)
    |> dedupe_fields

  ast.Struct(merged, trailing_comments: [])
}

/// Removes duplicate field names, keeping the last occurrence (allows overrides).
/// Returns fields sorted by name for consistent output.
fn dedupe_fields(fields: List(Field)) -> List(Field) {
  fields
  |> list.fold(dict.new(), fn(acc, field) {
    dict.insert(acc, field.name, field)
  })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { pair.1 })
}

/// Converts a struct's type-valued fields to a params dict.
/// Resolves type alias references before storing.
fn struct_to_params(
  s: Struct,
  type_aliases: Dict(String, ParsedType),
) -> Dict(String, AcceptedTypes) {
  s.fields
  |> list.filter_map(fn(field) {
    case field.value {
      ast.TypeValue(t) -> {
        let resolved = resolve_type_aliases(t, type_aliases)
        Ok(#(field.name, resolved))
      }
      ast.LiteralValue(_) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Resolves all ParsedTypeAliasRef instances, converting ParsedType to AcceptedTypes.
/// This is the resolution boundary where parsed types become fully resolved types.
fn resolve_type_aliases(
  t: ParsedType,
  aliases: Dict(String, ParsedType),
) -> AcceptedTypes {
  case t {
    ParsedPrimitive(p) -> PrimitiveType(p)
    ParsedTypeAliasRef(name) ->
      case dict.get(aliases, name) {
        Ok(resolved) -> resolve_type_aliases(resolved, aliases)
        // Unreachable after validation, but fall through gracefully
        Error(_) -> PrimitiveType(types.String)
      }
    ParsedCollection(collection) ->
      CollectionType(resolve_collection(collection, aliases))
    ParsedModifier(modifier) ->
      ModifierType(resolve_modifier(modifier, aliases))
    ParsedRefinement(refinement) ->
      RefinementType(resolve_refinement(refinement, aliases))
    ParsedRecord(fields) ->
      RecordType(
        dict.map_values(fields, fn(_, v) { resolve_type_aliases(v, aliases) }),
      )
  }
}

/// Resolves inner types of a collection.
fn resolve_collection(
  collection: types.CollectionTypes(ParsedType),
  aliases: Dict(String, ParsedType),
) -> types.CollectionTypes(AcceptedTypes) {
  case collection {
    List(inner) -> List(resolve_type_aliases(inner, aliases))
    Dict(key, value) ->
      Dict(
        resolve_type_aliases(key, aliases),
        resolve_type_aliases(value, aliases),
      )
  }
}

/// Resolves inner types of a modifier.
fn resolve_modifier(
  modifier: types.ModifierTypes(ParsedType),
  aliases: Dict(String, ParsedType),
) -> types.ModifierTypes(AcceptedTypes) {
  case modifier {
    Optional(inner) -> Optional(resolve_type_aliases(inner, aliases))
    Defaulted(inner, default) ->
      Defaulted(resolve_type_aliases(inner, aliases), default)
  }
}

/// Resolves inner types of a refinement.
fn resolve_refinement(
  refinement: types.RefinementTypes(ParsedType),
  aliases: Dict(String, ParsedType),
) -> types.RefinementTypes(AcceptedTypes) {
  case refinement {
    OneOf(inner, values) -> OneOf(resolve_type_aliases(inner, aliases), values)
    InclusiveRange(inner, low, high) ->
      InclusiveRange(resolve_type_aliases(inner, aliases), low, high)
  }
}

/// Converts a struct's literal-valued fields to an inputs dict.
fn struct_to_inputs(s: Struct) -> Dict(String, value.Value) {
  s.fields
  |> list.filter_map(fn(field) {
    case field.value {
      ast.LiteralValue(lit) -> Ok(#(field.name, literal_to_value(lit)))
      ast.TypeValue(_) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Converts a literal AST value to a typed Value.
@internal
pub fn literal_to_value(lit: Literal) -> value.Value {
  case lit {
    ast.LiteralString(s) -> value.StringValue(transform_template_vars(s))
    ast.LiteralInteger(i) -> value.IntValue(i)
    ast.LiteralFloat(f) -> value.FloatValue(f)
    ast.LiteralPercentage(f) -> value.PercentageValue(f)
    ast.LiteralDuration(amount, unit) ->
      case value.duration_unit_from_string(unit) {
        Ok(parsed_unit) -> value.DurationValue(amount, parsed_unit)
        // Tokenizer only emits known suffixes, so this branch is unreachable.
        // Fall back to NilValue rather than crashing.
        Error(Nil) -> value.NilValue
      }
    ast.LiteralTrue -> value.BoolValue(True)
    ast.LiteralFalse -> value.BoolValue(False)
    ast.LiteralList(elements) ->
      value.ListValue(list.map(elements, literal_to_value))
    ast.LiteralStruct(fields, _trailing_comments) ->
      fields
      |> list.filter_map(fn(field) {
        case field.value {
          ast.LiteralValue(inner) -> Ok(#(field.name, literal_to_value(inner)))
          ast.TypeValue(_) -> Error(Nil)
        }
      })
      |> dict.from_list
      |> value.DictValue
  }
}

/// Transforms template variables from $var->attr$ to $$var->attr$$ format.
/// Also handles $var->attr.not$ to $$var->attr:not$$ format.
fn transform_template_vars(s: String) -> String {
  transform_template_vars_loop(s, [])
}

fn transform_template_vars_loop(
  remaining: String,
  acc: List(String),
) -> String {
  case string.split_once(remaining, "$") {
    Ok(#(before, after)) -> {
      // Check if this is an escaped $$ (already transformed)
      case string.starts_with(after, "$") {
        True -> {
          // Skip escaped $$, keep both dollars
          transform_template_vars_loop(string.drop_start(after, 1), [
            "$$",
            before,
            ..acc
          ])
        }
        False -> {
          // Found single $, now find the closing $
          case string.split_once(after, "$") {
            Ok(#(var_content, rest)) -> {
              // Transform the variable content: .not -> :not
              let transformed = string.replace(var_content, ".not", ":not")
              transform_template_vars_loop(rest, [
                "$$",
                transformed,
                "$$",
                before,
                ..acc
              ])
            }
            Error(Nil) -> {
              // No closing $, just append as-is
              string.concat(list.reverse([after, "$", before, ..acc]))
            }
          }
        }
      }
    }
    Error(Nil) -> {
      // No more $, append the rest and we're done
      string.concat(list.reverse([remaining, ..acc]))
    }
  }
}
