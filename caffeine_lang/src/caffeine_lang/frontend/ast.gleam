/// AST for Caffeine blueprint and expectation files.
import caffeine_lang/types.{type ParsedType}
import gleam/list
import gleam/string

// =============================================================================
// COMMENTS
// =============================================================================

/// A comment attached to an AST node.
pub type Comment {
  LineComment(text: String)
  SectionComment(text: String)
}

// =============================================================================
// FILE-LEVEL NODES
// =============================================================================

/// Marker type for parsed (not yet validated) AST.
pub type Parsed

/// Marker type for validated AST.
pub type Validated

/// A blueprints file containing type aliases, extendables, and blueprint blocks.
/// Type aliases must come before extendables, which must come before blocks.
/// The phantom `phase` parameter tracks whether the file has been validated.
pub type BlueprintsFile(phase) {
  BlueprintsFile(
    type_aliases: List(TypeAlias),
    extendables: List(Extendable),
    blocks: List(BlueprintsBlock),
    trailing_comments: List(Comment),
  )
}

// =============================================================================
// TYPE ALIASES
// =============================================================================

/// A type alias that defines a named, reusable refined type.
/// Example: _env (Type): String { x | x in { prod, staging, dev } }
pub type TypeAlias {
  TypeAlias(name: String, type_: ParsedType, leading_comments: List(Comment))
}

/// An expects file containing extendables and expects blocks.
/// The phantom `phase` parameter tracks whether the file has been validated.
pub type ExpectsFile(phase) {
  ExpectsFile(
    extendables: List(Extendable),
    blocks: List(ExpectsBlock),
    trailing_comments: List(Comment),
  )
}

/// Promotes a BlueprintsFile to a new phantom phase by reconstructing all fields.
@internal
pub fn promote_blueprints_file(file: BlueprintsFile(a)) -> BlueprintsFile(b) {
  BlueprintsFile(
    type_aliases: file.type_aliases,
    extendables: file.extendables,
    blocks: file.blocks,
    trailing_comments: file.trailing_comments,
  )
}

/// Promotes an ExpectsFile to a new phantom phase by reconstructing all fields.
@internal
pub fn promote_expects_file(file: ExpectsFile(a)) -> ExpectsFile(b) {
  ExpectsFile(
    extendables: file.extendables,
    blocks: file.blocks,
    trailing_comments: file.trailing_comments,
  )
}

// =============================================================================
// EXTENDABLES
// =============================================================================

/// An extendable block that can be inherited by blueprints or expectations.
/// Extendables are always Requiring-kind, containing typed fields.
pub type Extendable {
  Extendable(name: String, body: Struct, leading_comments: List(Comment))
}

// =============================================================================
// BLUEPRINT NODES
// =============================================================================

/// A block of blueprints.
pub type BlueprintsBlock {
  BlueprintsBlock(items: List(BlueprintItem), leading_comments: List(Comment))
}

/// A single blueprint item with name, extends, requires, and provides.
pub type BlueprintItem {
  BlueprintItem(
    name: String,
    extends: List(String),
    requires: Struct,
    provides: Struct,
    leading_comments: List(Comment),
  )
}

// =============================================================================
// EXPECTS NODES
// =============================================================================

/// A block of expectations for a blueprint.
pub type ExpectsBlock {
  ExpectsBlock(
    blueprint: String,
    items: List(ExpectItem),
    leading_comments: List(Comment),
  )
}

/// A single expectation item with name, extends, and provides.
pub type ExpectItem {
  ExpectItem(
    name: String,
    extends: List(String),
    provides: Struct,
    leading_comments: List(Comment),
  )
}

// =============================================================================
// STRUCT AND FIELD
// =============================================================================

/// A struct containing a list of fields.
pub type Struct {
  Struct(fields: List(Field), trailing_comments: List(Comment))
}

/// A field with a name and value (either a type or a literal).
pub type Field {
  Field(name: String, value: Value, leading_comments: List(Comment))
}

/// A value in a field - either a type (in Requiring) or a literal (in Provides).
pub type Value {
  TypeValue(type_: ParsedType)
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
  LiteralPercentage(value: Float)
  LiteralTrue
  LiteralFalse
  LiteralList(elements: List(Literal))
  LiteralStruct(fields: List(Field), trailing_comments: List(Comment))
}

/// Builds a list of name-type pairs from type aliases for lookup purposes.
/// Used by both the validator and generator to resolve type alias references.
@internal
pub fn build_type_alias_pairs(
  type_aliases: List(TypeAlias),
) -> List(#(String, ParsedType)) {
  list.map(type_aliases, fn(ta) { #(ta.name, ta.type_) })
}

/// Converts a value to a display string.
@internal
pub fn value_to_string(value: Value) -> String {
  case value {
    TypeValue(t) -> types.parsed_type_to_string(t)
    LiteralValue(lit) -> literal_to_string(lit)
  }
}

/// Converts a literal to a short display string.
@internal
pub fn literal_to_string(lit: Literal) -> String {
  case lit {
    LiteralString(s) -> "\"" <> s <> "\""
    LiteralInteger(n) -> string.inspect(n)
    LiteralFloat(f) -> string.inspect(f)
    LiteralPercentage(f) -> string.inspect(f) <> "%"
    LiteralTrue -> "true"
    LiteralFalse -> "false"
    LiteralList(_) -> "[...]"
    LiteralStruct(_, _) -> "{...}"
  }
}
