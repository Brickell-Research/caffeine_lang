/// Validation for Caffeine frontend AST.
/// Handles extendable-related validation that must occur before JSON generation.
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable, type Field, type TypeAlias,
}
import caffeine_lang/types.{
  type ParsedType, type PrimitiveTypes, Boolean, Defaulted, Dict, InclusiveRange,
  NumericType, OneOf, ParsedCollection, ParsedModifier, ParsedPrimitive,
  ParsedRefinement, ParsedTypeAliasRef, Percentage, SemanticType,
  String as StringType,
}
import gleam/bool
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// Errors that can occur during validation.
pub type ValidatorError {
  DuplicateExtendable(name: String)
  UndefinedExtendable(
    name: String,
    referenced_by: String,
    candidates: List(String),
  )
  DuplicateExtendsReference(name: String, referenced_by: String)
  InvalidExtendableKind(name: String, expected: String, got: String)
  UndefinedTypeAlias(
    name: String,
    referenced_by: String,
    candidates: List(String),
  )
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
  InvalidRefinementValue(
    value: String,
    expected_type: String,
    referenced_by: String,
  )
  InvalidPercentageBounds(value: String, referenced_by: String)
}

/// Validates a blueprints file.
/// Checks for duplicate extendables, undefined extendable references,
/// duplicate type aliases, circular type aliases, undefined type alias references,
/// and that Dict key type aliases resolve to String-based types.
/// Returns all independent validation errors instead of stopping at the first.
@internal
pub fn validate_blueprints_file(
  file: BlueprintsFile,
) -> Result(BlueprintsFile, List(ValidatorError)) {
  let type_aliases = file.type_aliases
  let extendables = file.extendables
  let items =
    file.blocks
    |> list.flat_map(fn(block) { block.items })

  // Group A: type alias structural checks (sequential — circularity depends on no dupes)
  let type_alias_errors =
    validate_no_duplicates(type_aliases, fn(ta) { ta.name }, DuplicateTypeAlias)
    |> result.try(fn(_) { validate_no_circular_type_aliases(type_aliases) })
    |> errors_to_list

  // Group C: extendable structural checks (independent of Group A)
  let extendable_errors =
    collect_errors([
      validate_no_duplicates(extendables, fn(e) { e.name }, DuplicateExtendable),
      validate_no_extendable_type_alias_collision(extendables, type_aliases),
    ])

  // If structural checks failed, skip dependent checks and return all errors so far
  let structural_errors = list.append(type_alias_errors, extendable_errors)
  use <- guard_errors(structural_errors)

  // Build lookup structures (safe because structural checks passed)
  let type_alias_names =
    type_aliases
    |> list.map(fn(ta) { ta.name })
    |> set.from_list
  let type_alias_map = build_type_alias_map(type_aliases)

  // Group B: type alias reference checks and refinement value checks
  let type_ref_errors =
    collect_errors([
      validate_type_aliases_type_refs(
        type_aliases,
        type_alias_names,
        type_alias_map,
      ),
      validate_extendables_type_refs(
        extendables,
        type_alias_names,
        type_alias_map,
      ),
      validate_blueprint_items_type_refs(
        items,
        type_alias_names,
        type_alias_map,
      ),
    ])

  // Group D: extends validation (depends on extendable structural checks passing)
  let extends_errors =
    validate_blueprint_items_extends(items, extendables) |> errors_to_list

  let dependent_errors = list.append(type_ref_errors, extends_errors)
  use <- guard_errors(dependent_errors)

  Ok(file)
}

/// Validates an expects file.
/// Checks for duplicate extendables, undefined extendable references,
/// and that all extendables are Provides kind.
/// Returns all independent validation errors instead of stopping at the first.
@internal
pub fn validate_expects_file(
  file: ExpectsFile,
) -> Result(ExpectsFile, List(ValidatorError)) {
  let extendables = file.extendables
  let items =
    file.blocks
    |> list.flat_map(fn(block) { block.items })

  // Structural checks (independent of each other)
  let structural_errors =
    collect_errors([
      validate_no_duplicates(extendables, fn(e) { e.name }, DuplicateExtendable),
      validate_extendables_are_provides(extendables),
    ])
  use <- guard_errors(structural_errors)

  // Depends on structural checks passing
  let extends_errors =
    validate_expect_items_extends(items, extendables) |> errors_to_list
  use <- guard_errors(extends_errors)

  Ok(file)
}

/// Validates that no two items in a list share the same name.
fn validate_no_duplicates(
  items: List(a),
  get_name: fn(a) -> String,
  make_error: fn(String) -> ValidatorError,
) -> Result(Nil, ValidatorError) {
  validate_no_duplicates_loop(items, get_name, make_error, set.new())
}

fn validate_no_duplicates_loop(
  items: List(a),
  get_name: fn(a) -> String,
  make_error: fn(String) -> ValidatorError,
  seen: set.Set(String),
) -> Result(Nil, ValidatorError) {
  case items {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      let name = get_name(first)
      use <- bool.guard(
        when: set.contains(seen, name),
        return: Error(make_error(name)),
      )
      validate_no_duplicates_loop(
        rest,
        get_name,
        make_error,
        set.insert(seen, name),
      )
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
    let requires_fields =
      item.requires.fields |> list.map(fn(f) { f.name }) |> set.from_list
    let provides_fields =
      item.provides.fields |> list.map(fn(f) { f.name }) |> set.from_list
    validate_no_overshadowing(
      item.name,
      item.extends,
      [requires_fields, provides_fields],
      extendable_map,
    )
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
    let provides_fields =
      item.provides.fields |> list.map(fn(f) { f.name }) |> set.from_list
    validate_no_overshadowing(
      item.name,
      item.extends,
      [provides_fields],
      extendable_map,
    )
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
        return: Error(UndefinedExtendable(
          name: first,
          referenced_by: item_name,
          candidates: set.to_list(extendable_names),
        )),
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

/// Validates that an item's field sets don't overshadow fields from its extended extendables.
fn validate_no_overshadowing(
  item_name: String,
  extends: List(String),
  field_sets: List(set.Set(String)),
  extendable_map: dict.Dict(String, set.Set(String)),
) -> Result(Nil, ValidatorError) {
  list.try_each(extends, fn(ext_name) {
    case dict.get(extendable_map, ext_name) {
      Error(_) -> Ok(Nil)
      Ok(ext_fields) ->
        list.try_each(field_sets, fn(item_fields) {
          case set.intersection(item_fields, ext_fields) |> set.to_list {
            [] -> Ok(Nil)
            [field, ..] ->
              Error(ExtendableOvershadowing(
                field_name: field,
                item_name: item_name,
                extendable_name: ext_name,
              ))
          }
        })
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
      case list.key_find(type_alias_map, name) {
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

/// Validates type alias definitions for type refs and refinement values.
fn validate_type_aliases_type_refs(
  type_aliases: List(TypeAlias),
  type_alias_names: set.Set(String),
  type_alias_map: List(#(String, ParsedType)),
) -> Result(Nil, ValidatorError) {
  list.try_each(type_aliases, fn(ta) {
    validate_type_refs(ta.type_, ta.name, type_alias_names, type_alias_map)
  })
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
/// Adds special Dict key validation and refinement value validation.
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
      Error(UndefinedTypeAlias(
        name: name,
        referenced_by: context_name,
        candidates: set.to_list(type_alias_names),
      ))
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
    // For refinements, validate values match the declared primitive type
    ParsedRefinement(refinement) -> {
      use _ <- result.try(validate_refinement_values(refinement, context_name))
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
      case list.key_find(type_alias_map, alias_name) {
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

// =============================================================================
// REFINEMENT VALUE VALIDATION
// =============================================================================

/// Validates that refinement string values match the declared primitive type.
fn validate_refinement_values(
  refinement: types.RefinementTypes(ParsedType),
  context_name: String,
) -> Result(Nil, ValidatorError) {
  case refinement {
    OneOf(inner, values) -> {
      case extract_primitive_from_parsed(inner) {
        Ok(primitive) ->
          values
          |> set.to_list
          |> list.try_each(fn(value) {
            validate_string_matches_primitive(value, primitive, context_name)
          })
        Error(_) -> Ok(Nil)
      }
    }
    InclusiveRange(inner, low, high) -> {
      case extract_primitive_from_parsed(inner) {
        Ok(primitive) -> {
          use _ <- result.try(validate_string_matches_primitive(
            low,
            primitive,
            context_name,
          ))
          validate_string_matches_primitive(high, primitive, context_name)
        }
        Error(_) -> Ok(Nil)
      }
    }
  }
}

/// Extracts the primitive type from a ParsedType, unwrapping Defaulted modifiers.
fn extract_primitive_from_parsed(typ: ParsedType) -> Result(PrimitiveTypes, Nil) {
  case typ {
    ParsedPrimitive(primitive) -> Ok(primitive)
    ParsedModifier(Defaulted(inner, _)) -> extract_primitive_from_parsed(inner)
    _ -> Error(Nil)
  }
}

/// Validates that a string value is valid for the given primitive type.
fn validate_string_matches_primitive(
  value: String,
  primitive: PrimitiveTypes,
  context_name: String,
) -> Result(Nil, ValidatorError) {
  let is_valid = case primitive {
    types.String -> True
    SemanticType(_) -> True
    Boolean -> value == "True" || value == "False"
    NumericType(types.Integer) -> result.is_ok(int.parse(value))
    NumericType(types.Float) -> result.is_ok(float.parse(value))
    NumericType(Percentage) -> {
      // Strip trailing % if present for parsing
      let raw = case string.ends_with(value, "%") {
        True -> string.drop_end(value, 1)
        False -> value
      }
      case float.parse(raw) {
        Ok(f) -> {
          use <- bool.guard(when: f <. 0.0 || f >. 100.0, return: {
            // Value parses but is out of range — percentage bounds error
            False
          })
          True
        }
        Error(_) -> False
      }
    }
  }
  case is_valid {
    True -> Ok(Nil)
    False ->
      case primitive {
        NumericType(Percentage) -> {
          // Distinguish parse failure from out-of-range
          let raw = case string.ends_with(value, "%") {
            True -> string.drop_end(value, 1)
            False -> value
          }
          case float.parse(raw) {
            Ok(_) ->
              Error(InvalidPercentageBounds(
                value: value,
                referenced_by: context_name,
              ))
            Error(_) ->
              Error(InvalidRefinementValue(
                value: value,
                expected_type: types.primitive_type_to_string(primitive),
                referenced_by: context_name,
              ))
          }
        }
        _ ->
          Error(InvalidRefinementValue(
            value: value,
            expected_type: types.primitive_type_to_string(primitive),
            referenced_by: context_name,
          ))
      }
  }
}

// =============================================================================
// ERROR ACCUMULATION HELPERS
// =============================================================================

/// Converts a single-error Result to a list of errors (empty on Ok).
fn errors_to_list(result: Result(Nil, ValidatorError)) -> List(ValidatorError) {
  case result {
    Ok(_) -> []
    Error(err) -> [err]
  }
}

/// Collects errors from a list of independent validation results.
fn collect_errors(
  results: List(Result(Nil, ValidatorError)),
) -> List(ValidatorError) {
  results |> list.flat_map(errors_to_list)
}

/// Guards against accumulated errors. If errors is non-empty, returns them;
/// otherwise continues with the provided callback.
fn guard_errors(
  errors: List(ValidatorError),
  otherwise: fn() -> Result(a, List(ValidatorError)),
) -> Result(a, List(ValidatorError)) {
  case errors {
    [] -> otherwise()
    _ -> Error(errors)
  }
}
