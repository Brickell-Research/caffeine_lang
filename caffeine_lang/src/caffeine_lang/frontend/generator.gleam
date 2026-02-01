/// Frontend generator for Caffeine AST.
/// Converts validated AST to Blueprint and Expectation types for the compiler pipeline.
import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type Literal, type Struct, type TypeAlias,
}
import caffeine_lang/parser/blueprints.{type Blueprint, Blueprint}
import caffeine_lang/parser/expectations.{type Expectation, Expectation}
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/list
import gleam/string

/// Generates blueprints from a validated blueprints AST.
@internal
pub fn generate_blueprints(file: BlueprintsFile) -> List(Blueprint) {
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

/// Generates expectations from a validated expects AST.
@internal
pub fn generate_expectations(file: ExpectsFile) -> List(Expectation) {
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

/// Builds a map of type alias name to its resolved type for quick lookup.
fn build_type_alias_map(
  type_aliases: List(TypeAlias),
) -> Dict(String, AcceptedTypes) {
  ast.build_type_alias_pairs(type_aliases)
  |> dict.from_list
}

/// Generates a single blueprint from an AST item.
fn generate_blueprint_item(
  item: BlueprintItem,
  artifacts: List(String),
  extendables: Dict(String, Extendable),
  type_aliases: Dict(String, AcceptedTypes),
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

/// Merges extended fields into a blueprint item's requires and provides.
/// Order: extended extendables left-to-right, then item's own fields (can override).
fn merge_blueprint_extends(
  item: BlueprintItem,
  extendables: Dict(String, Extendable),
) -> #(Struct, Struct) {
  let requires_fields =
    item.extends
    |> list.flat_map(fn(name) {
      case dict.get(extendables, name) {
        Ok(ext) ->
          case ext.kind {
            ast.ExtendableRequires -> ext.body.fields
            ast.ExtendableProvides -> []
          }
        Error(_) -> []
      }
    })
    |> list.append(item.requires.fields)
    |> dedupe_fields

  let provides_fields =
    item.extends
    |> list.flat_map(fn(name) {
      case dict.get(extendables, name) {
        Ok(ext) ->
          case ext.kind {
            ast.ExtendableProvides -> ext.body.fields
            ast.ExtendableRequires -> []
          }
        Error(_) -> []
      }
    })
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
    item.extends
    |> list.flat_map(fn(name) {
      case dict.get(extendables, name) {
        Ok(ext) -> ext.body.fields
        Error(_) -> []
      }
    })
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
  type_aliases: Dict(String, AcceptedTypes),
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

/// Resolves all TypeAliasRef instances in a type by looking them up in the alias map.
/// Recursively resolves nested types using map_inner for structural decomposition.
fn resolve_type_aliases(
  t: AcceptedTypes,
  aliases: Dict(String, AcceptedTypes),
) -> AcceptedTypes {
  case t {
    accepted_types.PrimitiveType(_) -> t
    accepted_types.TypeAliasRef(name) ->
      case dict.get(aliases, name) {
        Ok(resolved) -> resolve_type_aliases(resolved, aliases)
        Error(_) -> t
      }
    // For compound types, recurse into inner types via map_inner
    _ ->
      accepted_types.map_inner(t, fn(inner) {
        resolve_type_aliases(inner, aliases)
      })
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
    ast.LiteralString(s) -> dynamic.from(transform_template_vars(s))
    ast.LiteralInteger(i) -> dynamic.from(i)
    ast.LiteralFloat(f) -> dynamic.from(f)
    ast.LiteralTrue -> dynamic.from(True)
    ast.LiteralFalse -> dynamic.from(False)
    ast.LiteralList(elements) ->
      dynamic.from(list.map(elements, literal_to_dynamic))
    ast.LiteralStruct(fields) ->
      dynamic.from(
        fields
        |> list.filter_map(fn(field) {
          case field.value {
            ast.LiteralValue(inner) ->
              Ok(#(field.name, literal_to_dynamic(inner)))
            ast.TypeValue(_) -> Error(Nil)
          }
        })
        |> dict.from_list,
      )
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
