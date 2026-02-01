/// JSON generator for Caffeine frontend AST.
/// Converts validated AST to JSON for the compiler pipeline.
import caffeine_lang/common/accepted_types.{type AcceptedTypes}
import caffeine_lang/common/collection_types
import caffeine_lang/common/modifier_types
import caffeine_lang/common/refinement_types
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type Literal, type Struct, type TypeAlias,
}
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/string

/// Generates JSON for a blueprints file.
@internal
pub fn generate_blueprints_json(file: BlueprintsFile) -> Json {
  let type_aliases = build_type_alias_map(file.type_aliases)
  let extendables = build_extendable_map(file.extendables)

  let blueprints =
    file.blocks
    |> list.flat_map(fn(block) {
      block.items
      |> list.map(fn(item) {
        generate_blueprint_item_json(
          item,
          block.artifacts,
          extendables,
          type_aliases,
        )
      })
    })

  json.object([#("blueprints", json.array(blueprints, fn(x) { x }))])
}

/// Generates JSON for an expects file.
@internal
pub fn generate_expects_json(file: ExpectsFile) -> Json {
  let extendables = build_extendable_map(file.extendables)

  let expectations =
    file.blocks
    |> list.flat_map(fn(block) {
      block.items
      |> list.map(fn(item) {
        generate_expect_item_json(item, block.blueprint, extendables)
      })
    })

  json.object([#("expectations", json.array(expectations, fn(x) { x }))])
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
  type_aliases
  |> list.map(fn(ta) { #(ta.name, ta.type_) })
  |> dict.from_list
}

/// Generates JSON for a single blueprint item.
fn generate_blueprint_item_json(
  item: BlueprintItem,
  artifacts: List(String),
  extendables: Dict(String, Extendable),
  type_aliases: Dict(String, AcceptedTypes),
) -> Json {
  // Merge extended fields into requires/provides
  let #(merged_requires, merged_provides) =
    merge_blueprint_extends(item, extendables)

  // Convert requires (types) to params, resolving type aliases
  let params = struct_to_params_json(merged_requires, type_aliases)

  // Convert provides (literals) to inputs
  let inputs = struct_to_inputs_json(merged_provides)

  json.object([
    #("name", json.string(item.name)),
    #("artifact_refs", json.array(artifacts, json.string)),
    #("params", params),
    #("inputs", inputs),
  ])
}

/// Generates JSON for a single expect item.
fn generate_expect_item_json(
  item: ExpectItem,
  blueprint: String,
  extendables: Dict(String, Extendable),
) -> Json {
  // Merge extended fields into provides
  let merged_provides = merge_expect_extends(item, extendables)

  // Convert provides (literals) to inputs
  let inputs = struct_to_inputs_json(merged_provides)

  json.object([
    #("name", json.string(item.name)),
    #("blueprint_ref", json.string(blueprint)),
    #("inputs", inputs),
  ])
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
/// Returns fields sorted by name for consistent JSON output.
fn dedupe_fields(fields: List(Field)) -> List(Field) {
  fields
  |> list.fold(dict.new(), fn(acc, field) {
    dict.insert(acc, field.name, field)
  })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { pair.1 })
}

/// Converts a struct with type values to a JSON params object.
/// Resolves type alias references before converting to strings.
fn struct_to_params_json(
  s: Struct,
  type_aliases: Dict(String, AcceptedTypes),
) -> Json {
  s.fields
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
  |> list.map(fn(field) {
    let type_string = case field.value {
      ast.TypeValue(t) -> {
        let resolved = resolve_type_aliases(t, type_aliases)
        accepted_types.accepted_type_to_string(resolved)
      }
      ast.LiteralValue(_) -> ""
    }
    #(field.name, json.string(type_string))
  })
  |> json.object
}

/// Resolves all TypeAliasRef instances in a type by looking them up in the alias map.
/// Recursively resolves nested types (in collections, modifiers, refinements).
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
    accepted_types.CollectionType(collection) ->
      accepted_types.CollectionType(resolve_collection_aliases(
        collection,
        aliases,
      ))
    accepted_types.ModifierType(modifier) ->
      accepted_types.ModifierType(resolve_modifier_aliases(modifier, aliases))
    accepted_types.RefinementType(refinement) ->
      accepted_types.RefinementType(resolve_refinement_aliases(
        refinement,
        aliases,
      ))
  }
}

/// Resolves type aliases in collection types.
fn resolve_collection_aliases(
  collection: collection_types.CollectionTypes(AcceptedTypes),
  aliases: Dict(String, AcceptedTypes),
) -> collection_types.CollectionTypes(AcceptedTypes) {
  case collection {
    collection_types.List(inner) ->
      collection_types.List(resolve_type_aliases(inner, aliases))
    collection_types.Dict(key, value) ->
      collection_types.Dict(
        resolve_type_aliases(key, aliases),
        resolve_type_aliases(value, aliases),
      )
  }
}

/// Resolves type aliases in modifier types.
fn resolve_modifier_aliases(
  modifier: modifier_types.ModifierTypes(AcceptedTypes),
  aliases: Dict(String, AcceptedTypes),
) -> modifier_types.ModifierTypes(AcceptedTypes) {
  case modifier {
    modifier_types.Optional(inner) ->
      modifier_types.Optional(resolve_type_aliases(inner, aliases))
    modifier_types.Defaulted(inner, default) ->
      modifier_types.Defaulted(resolve_type_aliases(inner, aliases), default)
  }
}

/// Resolves type aliases in refinement types.
fn resolve_refinement_aliases(
  refinement: refinement_types.RefinementTypes(AcceptedTypes),
  aliases: Dict(String, AcceptedTypes),
) -> refinement_types.RefinementTypes(AcceptedTypes) {
  case refinement {
    refinement_types.OneOf(inner, values) ->
      refinement_types.OneOf(resolve_type_aliases(inner, aliases), values)
    refinement_types.InclusiveRange(inner, min, max) ->
      refinement_types.InclusiveRange(
        resolve_type_aliases(inner, aliases),
        min,
        max,
      )
  }
}

/// Converts a struct with literal values to a JSON inputs object.
fn struct_to_inputs_json(s: Struct) -> Json {
  s.fields
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
  |> list.map(fn(field) {
    let json_value = case field.value {
      ast.LiteralValue(lit) -> literal_to_json(lit)
      ast.TypeValue(_) -> json.null()
    }
    #(field.name, json_value)
  })
  |> json.object
}

/// Converts a literal to a JSON value.
fn literal_to_json(lit: Literal) -> Json {
  case lit {
    ast.LiteralString(s) -> json.string(transform_template_vars(s))
    ast.LiteralInteger(i) -> json.int(i)
    ast.LiteralFloat(f) -> json.float(f)
    ast.LiteralTrue -> json.bool(True)
    ast.LiteralFalse -> json.bool(False)
    ast.LiteralList(elements) ->
      json.array(elements, fn(e) { literal_to_json(e) })
    ast.LiteralStruct(fields) -> literal_struct_to_json(fields)
  }
}

/// Converts a literal struct's fields to a JSON object.
fn literal_struct_to_json(fields: List(Field)) -> Json {
  fields
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
  |> list.map(fn(field) {
    let json_value = case field.value {
      ast.LiteralValue(lit) -> literal_to_json(lit)
      ast.TypeValue(_) -> json.null()
    }
    #(field.name, json_value)
  })
  |> json.object
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
