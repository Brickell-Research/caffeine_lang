/// Validation for Caffeine frontend AST.
/// Handles extendable-related validation that must occur before JSON generation.
import caffeine_lang/common/types.{
  type ParsedType, Dict, OneOf, ParsedCollection, ParsedPrimitive,
  ParsedRefinement, ParsedTypeAliasRef, String as StringType,
}
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type TypeAlias,
}
import gleam/bool
import gleam/dict
import gleam/list
import gleam/result
import gleam/set

/// Errors that can occur during validation.
pub type ValidatorError {
  DuplicateExtendable(name: String)
  UndefinedExtendable(name: String, referenced_by: String)
  DuplicateExtendsReference(name: String, referenced_by: String)
  InvalidExtendableKind(name: String, expected: String, got: String)
  UndefinedTypeAlias(name: String, referenced_by: String)
  DuplicateTypeAlias(name: String)
  CircularTypeAlias(name: String, cycle: List(String))
  InvalidDictKeyTypeAlias(
    alias_name: String,
    resolved_to: String,
    referenced_by: String,
  )
  ExtendableOvershadowing(
    field_name: String,
    item_name: String,
    extendable_name: String,
  )
  ExtendableTypeAliasNameCollision(name: String)
}

/// Validates a blueprints file.
/// Checks for duplicate extendables, undefined extendable references,
/// duplicate type aliases, circular type aliases, undefined type alias references,
/// and that Dict key type aliases resolve to String-based types.
@internal
pub fn validate_blueprints_file(
  file: BlueprintsFile,
) -> Result(BlueprintsFile, ValidatorError) {
  let type_aliases = file.type_aliases
  let extendables = file.extendables
  let items =
    file.blocks
    |> list.flat_map(fn(block) { block.items })

  // Validate type aliases first
  use _ <- result.try(validate_no_duplicate_type_aliases(type_aliases))
  use _ <- result.try(validate_no_circular_type_aliases(type_aliases))

  // Build set of defined type alias names for reference validation
  let type_alias_names =
    type_aliases
    |> list.map(fn(ta) { ta.name })
    |> set.from_list

  // Build map for Dict key validation
  let type_alias_map = build_type_alias_map(type_aliases)

  // Validate type alias references in extendables
  use _ <- result.try(validate_extendables_type_refs(
    extendables,
    type_alias_names,
    type_alias_map,
  ))

  // Validate type alias references in blueprint items
  use _ <- result.try(validate_blueprint_items_type_refs(
    items,
    type_alias_names,
    type_alias_map,
  ))

  use _ <- result.try(validate_no_duplicate_extendables(extendables))
  use _ <- result.try(validate_no_extendable_type_alias_collision(
    extendables,
    type_aliases,
  ))
  use _ <- result.try(validate_blueprint_items_extends(items, extendables))

  Ok(file)
}

/// Validates an expects file.
/// Checks for duplicate extendables, undefined extendable references,
/// and that all extendables are Provides kind.
@internal
pub fn validate_expects_file(
  file: ExpectsFile,
) -> Result(ExpectsFile, ValidatorError) {
  let extendables = file.extendables
  let items =
    file.blocks
    |> list.flat_map(fn(block) { block.items })

  use _ <- result.try(validate_no_duplicate_extendables(extendables))
  use _ <- result.try(validate_extendables_are_provides(extendables))
  use _ <- result.try(validate_expect_items_extends(items, extendables))

  Ok(file)
}

/// Validates that no two extendables have the same name.
fn validate_no_duplicate_extendables(
  extendables: List(Extendable),
) -> Result(Nil, ValidatorError) {
  validate_no_duplicate_extendables_loop(extendables, set.new())
}

fn validate_no_duplicate_extendables_loop(
  extendables: List(Extendable),
  seen: set.Set(String),
) -> Result(Nil, ValidatorError) {
  case extendables {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      use <- bool.guard(
        when: set.contains(seen, first.name),
        return: Error(DuplicateExtendable(name: first.name)),
      )
      validate_no_duplicate_extendables_loop(rest, set.insert(seen, first.name))
    }
  }
}

/// Validates that no extendable shares a name with a type alias.
fn validate_no_extendable_type_alias_collision(
  extendables: List(Extendable),
  type_aliases: List(TypeAlias),
) -> Result(Nil, ValidatorError) {
  let type_alias_names =
    type_aliases
    |> list.map(fn(ta) { ta.name })
    |> set.from_list

  list.try_each(extendables, fn(ext) {
    use <- bool.guard(
      when: set.contains(type_alias_names, ext.name),
      return: Error(ExtendableTypeAliasNameCollision(name: ext.name)),
    )
    Ok(Nil)
  })
}

/// Validates that all extendables in an expects file are Provides kind.
fn validate_extendables_are_provides(
  extendables: List(Extendable),
) -> Result(Nil, ValidatorError) {
  case extendables {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      case first.kind {
        ast.ExtendableProvides -> validate_extendables_are_provides(rest)
        ast.ExtendableRequires ->
          Error(InvalidExtendableKind(
            name: first.name,
            expected: "Provides",
            got: "Requires",
          ))
      }
    }
  }
}

/// Validates extends references for blueprint items.
fn validate_blueprint_items_extends(
  items: List(BlueprintItem),
  extendables: List(Extendable),
) -> Result(Nil, ValidatorError) {
  let extendable_names =
    extendables
    |> list.map(fn(e) { e.name })
    |> set.from_list

  let extendable_map = build_extendable_field_map(extendables)

  list.try_each(items, fn(item) {
    use _ <- result.try(validate_extends_exist(
      item.extends,
      item.name,
      extendable_names,
    ))
    use _ <- result.try(validate_no_duplicate_extends(item.extends, item.name))
    // Check that item's requires/provides don't overshadow extended fields
    validate_no_blueprint_overshadowing(item, extendable_map)
  })
}

/// Validates extends references for expect items.
fn validate_expect_items_extends(
  items: List(ExpectItem),
  extendables: List(Extendable),
) -> Result(Nil, ValidatorError) {
  let extendable_names =
    extendables
    |> list.map(fn(e) { e.name })
    |> set.from_list

  let extendable_map = build_extendable_field_map(extendables)

  list.try_each(items, fn(item) {
    use _ <- result.try(validate_extends_exist(
      item.extends,
      item.name,
      extendable_names,
    ))
    use _ <- result.try(validate_no_duplicate_extends(item.extends, item.name))
    // Check that item's provides don't overshadow extended fields
    validate_no_expect_overshadowing(item, extendable_map)
  })
}

/// Validates that all names in extends list exist as extendables.
fn validate_extends_exist(
  extends: List(String),
  item_name: String,
  extendable_names: set.Set(String),
) -> Result(Nil, ValidatorError) {
  case extends {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      use <- bool.guard(
        when: !set.contains(extendable_names, first),
        return: Error(UndefinedExtendable(name: first, referenced_by: item_name)),
      )
      validate_extends_exist(rest, item_name, extendable_names)
    }
  }
}

/// Validates that no extendable is referenced twice in the same extends list.
fn validate_no_duplicate_extends(
  extends: List(String),
  item_name: String,
) -> Result(Nil, ValidatorError) {
  validate_no_duplicate_extends_loop(extends, item_name, set.new())
}

fn validate_no_duplicate_extends_loop(
  extends: List(String),
  item_name: String,
  seen: set.Set(String),
) -> Result(Nil, ValidatorError) {
  case extends {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      use <- bool.guard(
        when: set.contains(seen, first),
        return: Error(DuplicateExtendsReference(
          name: first,
          referenced_by: item_name,
        )),
      )
      validate_no_duplicate_extends_loop(
        rest,
        item_name,
        set.insert(seen, first),
      )
    }
  }
}

/// Builds a map of extendable name to its field names for overshadowing checks.
fn build_extendable_field_map(
  extendables: List(Extendable),
) -> dict.Dict(String, set.Set(String)) {
  extendables
  |> list.map(fn(e) {
    let field_names =
      e.body.fields
      |> list.map(fn(f) { f.name })
      |> set.from_list
    #(e.name, field_names)
  })
  |> dict.from_list
}

/// Validates that a blueprint item doesn't overshadow fields from its extended extendables.
fn validate_no_blueprint_overshadowing(
  item: BlueprintItem,
  extendable_map: dict.Dict(String, set.Set(String)),
) -> Result(Nil, ValidatorError) {
  // Get all field names from item's requires and provides
  let item_requires_fields =
    item.requires.fields
    |> list.map(fn(f) { f.name })
    |> set.from_list
  let item_provides_fields =
    item.provides.fields
    |> list.map(fn(f) { f.name })
    |> set.from_list

  // Check each extended extendable for overshadowing
  list.try_each(item.extends, fn(ext_name) {
    case dict.get(extendable_map, ext_name) {
      Error(_) -> Ok(Nil)
      Ok(ext_fields) -> {
        // Check requires overshadowing
        let requires_overlap =
          set.intersection(item_requires_fields, ext_fields)
        use _ <- result.try(case set.to_list(requires_overlap) {
          [] -> Ok(Nil)
          [field, ..] ->
            Error(ExtendableOvershadowing(
              field_name: field,
              item_name: item.name,
              extendable_name: ext_name,
            ))
        })
        // Check provides overshadowing
        let provides_overlap =
          set.intersection(item_provides_fields, ext_fields)
        case set.to_list(provides_overlap) {
          [] -> Ok(Nil)
          [field, ..] ->
            Error(ExtendableOvershadowing(
              field_name: field,
              item_name: item.name,
              extendable_name: ext_name,
            ))
        }
      }
    }
  })
}

/// Validates that an expect item doesn't overshadow fields from its extended extendables.
fn validate_no_expect_overshadowing(
  item: ExpectItem,
  extendable_map: dict.Dict(String, set.Set(String)),
) -> Result(Nil, ValidatorError) {
  // Get all field names from item's provides
  let item_provides_fields =
    item.provides.fields
    |> list.map(fn(f) { f.name })
    |> set.from_list

  // Check each extended extendable for overshadowing
  list.try_each(item.extends, fn(ext_name) {
    case dict.get(extendable_map, ext_name) {
      Error(_) -> Ok(Nil)
      Ok(ext_fields) -> {
        let provides_overlap =
          set.intersection(item_provides_fields, ext_fields)
        case set.to_list(provides_overlap) {
          [] -> Ok(Nil)
          [field, ..] ->
            Error(ExtendableOvershadowing(
              field_name: field,
              item_name: item.name,
              extendable_name: ext_name,
            ))
        }
      }
    }
  })
}

// =============================================================================
// TYPE ALIAS VALIDATION
// =============================================================================

/// Builds a map of type alias name to its type for validation.
fn build_type_alias_map(
  type_aliases: List(TypeAlias),
) -> List(#(String, ParsedType)) {
  ast.build_type_alias_pairs(type_aliases)
}

/// Looks up a type alias by name in the map.
fn lookup_type_alias(
  name: String,
  type_alias_map: List(#(String, ParsedType)),
) -> Result(ParsedType, Nil) {
  case type_alias_map {
    [] -> Error(Nil)
    [#(n, t), ..rest] -> {
      use <- bool.guard(when: n == name, return: Ok(t))
      lookup_type_alias(name, rest)
    }
  }
}

/// Validates that no two type aliases have the same name.
fn validate_no_duplicate_type_aliases(
  type_aliases: List(TypeAlias),
) -> Result(Nil, ValidatorError) {
  validate_no_duplicate_type_aliases_loop(type_aliases, set.new())
}

fn validate_no_duplicate_type_aliases_loop(
  type_aliases: List(TypeAlias),
  seen: set.Set(String),
) -> Result(Nil, ValidatorError) {
  case type_aliases {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      use <- bool.guard(
        when: set.contains(seen, first.name),
        return: Error(DuplicateTypeAlias(name: first.name)),
      )
      validate_no_duplicate_type_aliases_loop(
        rest,
        set.insert(seen, first.name),
      )
    }
  }
}

/// Validates that no type alias has circular references.
fn validate_no_circular_type_aliases(
  type_aliases: List(TypeAlias),
) -> Result(Nil, ValidatorError) {
  let type_alias_map = build_type_alias_map(type_aliases)
  list.try_each(type_aliases, fn(ta) {
    validate_type_alias_not_circular(ta.name, ta.type_, type_alias_map, [
      ta.name,
    ])
  })
}

/// Checks if a type contains a circular reference.
/// Uses try_each_inner_parsed to handle the structural decomposition of compound types,
/// with leaf-specific logic for ParsedPrimitive and ParsedTypeAliasRef.
fn validate_type_alias_not_circular(
  original_name: String,
  typ: ParsedType,
  type_alias_map: List(#(String, ParsedType)),
  visited: List(String),
) -> Result(Nil, ValidatorError) {
  case typ {
    ParsedPrimitive(_) -> Ok(Nil)
    ParsedTypeAliasRef(name) -> {
      use <- bool.guard(
        when: list.contains(visited, name),
        return: Error(CircularTypeAlias(name: original_name, cycle: visited)),
      )
      case lookup_type_alias(name, type_alias_map) {
        Ok(resolved) ->
          validate_type_alias_not_circular(
            original_name,
            resolved,
            type_alias_map,
            [name, ..visited],
          )
        // Undefined ref is caught elsewhere
        Error(_) -> Ok(Nil)
      }
    }
    // For compound types, decompose and recurse via try_each_inner_parsed
    _ ->
      types.try_each_inner_parsed(typ, fn(inner) {
        validate_type_alias_not_circular(
          original_name,
          inner,
          type_alias_map,
          visited,
        )
      })
  }
}

/// Validates type alias references in extendables.
fn validate_extendables_type_refs(
  extendables: List(Extendable),
  type_alias_names: set.Set(String),
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  list.try_each(extendables, fn(ext) {
    validate_fields_type_refs(
      ext.body.fields,
      ext.name,
      type_alias_names,
      type_alias_map,
    )
  })
}

/// Validates type alias references in blueprint items.
fn validate_blueprint_items_type_refs(
  items: List(BlueprintItem),
  type_alias_names: set.Set(String),
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  list.try_each(items, fn(item) {
    validate_fields_type_refs(
      item.requires.fields,
      item.name,
      type_alias_names,
      type_alias_map,
    )
  })
}

/// Validates type alias references in a list of fields.
fn validate_fields_type_refs(
  fields: List(Field),
  context_name: String,
  type_alias_names: set.Set(String),
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  list.try_each(fields, fn(field) {
    case field.value {
      ast.TypeValue(typ) ->
        validate_type_refs(typ, context_name, type_alias_names, type_alias_map)
      ast.LiteralValue(_) -> Ok(Nil)
    }
  })
}

/// Validates that all ParsedTypeAliasRef in a type are defined.
/// Uses try_each_inner_parsed to handle the structural decomposition of compound types.
/// Adds special Dict key validation for collection types.
fn validate_type_refs(
  typ: ParsedType,
  context_name: String,
  type_alias_names: set.Set(String),
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  case typ {
    ParsedPrimitive(_) -> Ok(Nil)
    ParsedTypeAliasRef(name) -> {
      use <- bool.guard(
        when: set.contains(type_alias_names, name),
        return: Ok(Nil),
      )
      Error(UndefinedTypeAlias(name: name, referenced_by: context_name))
    }
    // For Dict, validate key type resolves to String-based before recursing
    ParsedCollection(Dict(key, _)) -> {
      use _ <- result.try(validate_dict_key_type(
        key,
        context_name,
        type_alias_map,
      ))
      types.try_each_inner_parsed(typ, fn(inner) {
        validate_type_refs(
          inner,
          context_name,
          type_alias_names,
          type_alias_map,
        )
      })
    }
    // For all other compound types, recurse via try_each_inner_parsed
    _ ->
      types.try_each_inner_parsed(typ, fn(inner) {
        validate_type_refs(
          inner,
          context_name,
          type_alias_names,
          type_alias_map,
        )
      })
  }
}

/// Validates that a Dict key type resolves to a String-based type.
fn validate_dict_key_type(
  key_type: ParsedType,
  context_name: String,
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  case key_type {
    // String primitive is always valid
    ParsedPrimitive(StringType) -> Ok(Nil)
    // ParsedTypeAliasRef must resolve to String-based type
    ParsedTypeAliasRef(alias_name) -> {
      case lookup_type_alias(alias_name, type_alias_map) {
        Ok(resolved) -> {
          use <- bool.guard(
            when: is_string_based_parsed_type(resolved),
            return: Ok(Nil),
          )
          Error(InvalidDictKeyTypeAlias(
            alias_name: alias_name,
            resolved_to: types.parsed_type_to_string(resolved),
            referenced_by: context_name,
          ))
        }
        Error(_) -> Ok(Nil)
        // Undefined ref is caught elsewhere
      }
    }
    // Refinement of String is valid
    ParsedRefinement(OneOf(ParsedPrimitive(StringType), _)) -> Ok(Nil)
    // Other types are not valid Dict keys
    _ ->
      Error(InvalidDictKeyTypeAlias(
        alias_name: "inline",
        resolved_to: types.parsed_type_to_string(key_type),
        referenced_by: context_name,
      ))
  }
}

/// Checks if a parsed type is String-based (String primitive or String refinement).
fn is_string_based_parsed_type(typ: ParsedType) -> Bool {
  case typ {
    ParsedPrimitive(StringType) -> True
    ParsedRefinement(OneOf(ParsedPrimitive(StringType), _)) -> True
    _ -> False
  }
}
