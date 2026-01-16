/// Validation for Caffeine frontend AST.
/// Handles extendable-related validation that must occur before JSON generation.
import caffeine_lang/frontend/ast.{
  type BlueprintItem, type BlueprintsFile, type ExpectItem, type ExpectsFile,
  type Extendable,
}
import gleam/list
import gleam/result
import gleam/set

/// Errors that can occur during validation.
pub type ValidatorError {
  DuplicateExtendable(name: String)
  UndefinedExtendable(name: String, referenced_by: String)
  DuplicateExtendsReference(name: String, referenced_by: String)
  InvalidExtendableKind(name: String, expected: String, got: String)
}

/// Validates a blueprints file.
/// Checks for duplicate extendables and undefined extendable references.
@internal
pub fn validate_blueprints_file(
  file: BlueprintsFile,
) -> Result(BlueprintsFile, ValidatorError) {
  let extendables = file.extendables
  let items =
    file.blocks
    |> list.flat_map(fn(block) { block.items })

  use _ <- result.try(validate_no_duplicate_extendables(extendables))
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
      case set.contains(seen, first.name) {
        True -> Error(DuplicateExtendable(name: first.name))
        False ->
          validate_no_duplicate_extendables_loop(
            rest,
            set.insert(seen, first.name),
          )
      }
    }
  }
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

  list.try_each(items, fn(item) {
    use _ <- result.try(validate_extends_exist(
      item.extends,
      item.name,
      extendable_names,
    ))
    validate_no_duplicate_extends(item.extends, item.name)
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

  list.try_each(items, fn(item) {
    use _ <- result.try(validate_extends_exist(
      item.extends,
      item.name,
      extendable_names,
    ))
    validate_no_duplicate_extends(item.extends, item.name)
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
      case set.contains(extendable_names, first) {
        True -> validate_extends_exist(rest, item_name, extendable_names)
        False ->
          Error(UndefinedExtendable(name: first, referenced_by: item_name))
      }
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
      case set.contains(seen, first) {
        True ->
          Error(DuplicateExtendsReference(name: first, referenced_by: item_name))
        False ->
          validate_no_duplicate_extends_loop(
            rest,
            item_name,
            set.insert(seen, first),
          )
      }
    }
  }
}
