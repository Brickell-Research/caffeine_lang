/// JSON generator for Caffeine frontend AST.
/// Converts validated AST to JSON for the compiler pipeline.
import caffeine_lang/common/accepted_types
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type Literal, type Struct,
}
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/string

/// Generates JSON for a blueprints file.
@internal
pub fn generate_blueprints_json(file: BlueprintsFile) -> Json {
  let extendables = build_extendable_map(file.extendables)

  let blueprints =
    file.blocks
    |> list.flat_map(fn(block) {
      block.items
      |> list.map(fn(item) {
        generate_blueprint_item_json(item, block.artifacts, extendables)
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

/// Generates JSON for a single blueprint item.
fn generate_blueprint_item_json(
  item: BlueprintItem,
  artifacts: List(String),
  extendables: Dict(String, Extendable),
) -> Json {
  // Merge extended fields into requires/provides
  let #(merged_requires, merged_provides) =
    merge_blueprint_extends(item, extendables)

  // Convert requires (types) to params
  let params = struct_to_params_json(merged_requires)

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

  #(ast.Struct(requires_fields), ast.Struct(provides_fields))
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

  ast.Struct(provides_fields)
}

/// Removes duplicate field names, keeping the last occurrence (allows overrides).
/// Returns fields sorted by name for consistent JSON output.
fn dedupe_fields(fields: List(Field)) -> List(Field) {
  fields
  |> list.fold(dict.new(), fn(acc, field) { dict.insert(acc, field.name, field) })
  |> dict.to_list
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { pair.1 })
}

/// Converts a struct with type values to a JSON params object.
fn struct_to_params_json(s: Struct) -> Json {
  s.fields
  |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
  |> list.map(fn(field) {
    let type_string = case field.value {
      ast.TypeValue(t) -> accepted_types.accepted_type_to_string(t)
      ast.LiteralValue(_) -> ""
    }
    #(field.name, json.string(type_string))
  })
  |> json.object
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

/// Transforms template variables from ${var->attr} to $$var->attr$$ format.
/// Also handles ${var->attr.not} to $$var->attr:not$$ format.
fn transform_template_vars(s: String) -> String {
  transform_template_vars_loop(s, "")
}

fn transform_template_vars_loop(remaining: String, acc: String) -> String {
  case string.split_once(remaining, "${") {
    Ok(#(before, after)) -> {
      // Found ${, now find the closing }
      case string.split_once(after, "}") {
        Ok(#(var_content, rest)) -> {
          // Transform the variable content: .not -> :not
          let transformed = string.replace(var_content, ".not", ":not")
          transform_template_vars_loop(rest, acc <> before <> "$$" <> transformed <> "$$")
        }
        Error(Nil) -> {
          // No closing }, just append as-is
          acc <> before <> "${" <> after
        }
      }
    }
    Error(Nil) -> {
      // No more ${, append the rest and we're done
      acc <> remaining
    }
  }
}
