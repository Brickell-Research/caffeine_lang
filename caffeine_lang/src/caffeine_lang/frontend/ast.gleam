/// AST for Caffeine blueprint and expectation files.
import caffeine_lang/common/accepted_types.{type AcceptedTypes}

// =============================================================================
// FILE-LEVEL NODES
// =============================================================================

/// A blueprints file containing type aliases, extendables, and blueprint blocks.
/// Type aliases must come before extendables, which must come before blocks.
pub type BlueprintsFile {
  BlueprintsFile(
    type_aliases: List(TypeAlias),
    extendables: List(Extendable),
    blocks: List(BlueprintsBlock),
  )
}

// =============================================================================
// TYPE ALIASES
// =============================================================================

/// A type alias that defines a named, reusable refined type.
/// Example: _env (Type): String { x | x in { prod, staging, dev } }
pub type TypeAlias {
  TypeAlias(name: String, type_: AcceptedTypes)
}

/// An expects file containing extendables and expects blocks.
pub type ExpectsFile {
  ExpectsFile(extendables: List(Extendable), blocks: List(ExpectsBlock))
}

// =============================================================================
// EXTENDABLES
// =============================================================================

/// An extendable block that can be inherited by blueprints or expectations.
pub type Extendable {
  Extendable(name: String, kind: ExtendableKind, body: Struct)
}

/// The kind of extendable (Requires for types, Provides for values).
pub type ExtendableKind {
  ExtendableRequires
  ExtendableProvides
}

// =============================================================================
// BLUEPRINT NODES
// =============================================================================

/// A block of blueprints for one or more artifacts.
pub type BlueprintsBlock {
  BlueprintsBlock(artifacts: List(String), items: List(BlueprintItem))
}

/// A single blueprint item with name, extends, requires, and provides.
pub type BlueprintItem {
  BlueprintItem(
    name: String,
    extends: List(String),
    requires: Struct,
    provides: Struct,
  )
}

// =============================================================================
// EXPECTS NODES
// =============================================================================

/// A block of expectations for a blueprint.
pub type ExpectsBlock {
  ExpectsBlock(blueprint: String, items: List(ExpectItem))
}

/// A single expectation item with name, extends, and provides.
pub type ExpectItem {
  ExpectItem(name: String, extends: List(String), provides: Struct)
}

// =============================================================================
// STRUCT AND FIELD
// =============================================================================

/// A struct containing a list of fields.
pub type Struct {
  Struct(fields: List(Field))
}

/// A field with a name and value (either a type or a literal).
pub type Field {
  Field(name: String, value: Value)
}

/// A value in a field - either a type (in Requires) or a literal (in Provides).
pub type Value {
  TypeValue(type_: AcceptedTypes)
  LiteralValue(literal: Literal)
}

// =============================================================================
// LITERALS
// =============================================================================

/// Literal values.
pub type Literal {
  LiteralString(value: String)
  LiteralInteger(value: Int)
  LiteralFloat(value: Float)
  LiteralTrue
  LiteralFalse
  LiteralList(elements: List(Literal))
  LiteralStruct(fields: List(Field))
}
