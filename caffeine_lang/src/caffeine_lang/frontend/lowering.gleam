/// Frontend lowering for Caffeine AST.
/// Converts validated AST to Blueprint and Expectation types for the compiler pipeline.
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type Literal, type Struct, type TypeAlias,
}
import caffeine_lang/linker/blueprints.{type Blueprint, Blueprint}
import caffeine_lang/linker/expectations.{type Expectation, Expectation}
import caffeine_lang/types.{
  type AcceptedTypes, type ParsedType, CollectionType, Defaulted, Dict,
  InclusiveRange, List, ModifierType, OneOf, Optional, ParsedCollection,
  ParsedModifier, ParsedPrimitive, ParsedRefinement, ParsedTypeAliasRef,
  PrimitiveType, RefinementType,
}
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/list
import gleam/string

/// Lowers blueprints from a validated blueprints AST.
@internal
pub fn lower_blueprints(file: BlueprintsFile) -> List(Blueprint) {
  let type_aliases = build_type_alias_map(file.type_aliases)
  let extendables = build_extendable_map(file.extendables)

  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.map(fn(item) {
      generate_blueprint_item(item, block.artifacts, extendables, type_aliases)
    })
  })
}

/// Lowers expectations from a validated expects AST.
@internal
pub fn lower_expectations(file: ExpectsFile) -> List(Expectation) {
  let extendables = build_extendable_map(file.extendables)

  file.blocks
  |> list.flat_map(fn(block) {
    block.items
    |> list.map(fn(item) {
      generate_expect_item(item, block.blueprint, extendables)
    })
  })
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

/// Generates a single blueprint from an AST item.
fn generate_blueprint_item(
  item: BlueprintItem,
  artifacts: List(String),
  extendables: Dict(String, Extendable),
  type_aliases: Dict(String, ParsedType),
) -> Blueprint {
  let #(merged_requires, merged_provides) =
    merge_blueprint_extends(item, extendables)

  let params = struct_to_params(merged_requires, type_aliases)
  let inputs = struct_to_inputs(merged_provides)

  Blueprint(
    name: item.name,
    artifact_refs: artifacts,
    params: params,
    inputs: inputs,
  )
}

/// Generates a single expectation from an AST item.
fn generate_expect_item(
  item: ExpectItem,
  blueprint: String,
  extendables: Dict(String, Extendable),
) -> Expectation {
  let merged_provides = merge_expect_extends(item, extendables)
  let inputs = struct_to_inputs(merged_provides)

  Expectation(name: item.name, blueprint_ref: blueprint, inputs: inputs)
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

/// Merges extended fields into a blueprint item's requires and provides.
/// Order: extended extendables left-to-right, then item's own fields (can override).
fn merge_blueprint_extends(
  item: BlueprintItem,
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

/// Merges extended fields into an expect item's provides.
/// Order: extended extendables left-to-right, then item's own fields (can override).
fn merge_expect_extends(
  item: ExpectItem,
  extendables: Dict(String, Extendable),
) -> Struct {
  let provides_fields =
    collect_extended_fields(item.extends, extendables, ast.ExtendableProvides)
    |> list.append(item.provides.fields)
    |> dedupe_fields

  ast.Struct(provides_fields, trailing_comments: [])
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
fn struct_to_inputs(s: Struct) -> Dict(String, dynamic.Dynamic) {
  s.fields
  |> list.filter_map(fn(field) {
    case field.value {
      ast.LiteralValue(lit) -> Ok(#(field.name, literal_to_dynamic(lit)))
      ast.TypeValue(_) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// Converts a literal AST value to a Dynamic value.
@internal
pub fn literal_to_dynamic(lit: Literal) -> dynamic.Dynamic {
  case lit {
    ast.LiteralString(s) -> dynamic.string(transform_template_vars(s))
    ast.LiteralInteger(i) -> dynamic.int(i)
    ast.LiteralFloat(f) -> dynamic.float(f)
    ast.LiteralTrue -> dynamic.bool(True)
    ast.LiteralFalse -> dynamic.bool(False)
    ast.LiteralList(elements) ->
      dynamic.list(list.map(elements, literal_to_dynamic))
    ast.LiteralStruct(fields) ->
      fields
      |> list.filter_map(fn(field) {
        case field.value {
          ast.LiteralValue(inner) ->
            Ok(#(dynamic.string(field.name), literal_to_dynamic(inner)))
          ast.TypeValue(_) -> Error(Nil)
        }
      })
      |> dynamic.properties
  }
}

/// Transforms template variables from $var->attr$ to $$var->attr$$ format.
/// Also handles $var->attr.not$ to $$var->attr:not$$ format.
fn transform_template_vars(s: String) -> String {
  transform_template_vars_loop(s, "")
}

fn transform_template_vars_loop(remaining: String, acc: String) -> String {
  case string.split_once(remaining, "$") {
    Ok(#(before, after)) -> {
      // Check if this is an escaped $$ (already transformed)
      case string.starts_with(after, "$") {
        True -> {
          // Skip escaped $$, keep both dollars
          transform_template_vars_loop(
            string.drop_start(after, 1),
            acc <> before <> "$$",
          )
        }
        False -> {
          // Found single $, now find the closing $
          case string.split_once(after, "$") {
            Ok(#(var_content, rest)) -> {
              // Transform the variable content: .not -> :not
              let transformed = string.replace(var_content, ".not", ":not")
              transform_template_vars_loop(
                rest,
                acc <> before <> "$$" <> transformed <> "$$",
              )
            }
            Error(Nil) -> {
              // No closing $, just append as-is
              acc <> before <> "$" <> after
            }
          }
        }
      }
    }
    Error(Nil) -> {
      // No more $, append the rest and we're done
      acc <> remaining
    }
  }
}
