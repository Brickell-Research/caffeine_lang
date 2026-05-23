/// AST for Caffeine measurement and expectation files.
import caffeine_lang/types.{type ParsedType}
import gleam/list
import gleam/option.{type Option}
import gleam/string

// =============================================================================
// COMMENTS
// =============================================================================

/// A comment attached to an AST node.
pub type Comment {
  LineComment(text: String)
  SectionComment(text: String)
  /// A `###`-prefixed doc comment. When attached to an `ExpectItem`'s
  /// `leading_comments`, the text becomes the SLO description in the Datadog
  /// Terraform output.
  DocComment(text: String)
}

// =============================================================================
// FILE-LEVEL NODES
// =============================================================================

/// Marker type for parsed (not yet validated) AST.
pub type Parsed

/// Marker type for validated AST.
pub type Validated

/// A measurements file containing type aliases, extendables, and measurement items.
/// Type aliases must come before extendables, which must come before items.
/// The phantom `phase` parameter tracks whether the file has been validated.
pub type MeasurementsFile(phase) {
  MeasurementsFile(
    type_aliases: List(TypeAlias),
    extendables: List(Extendable),
    items: List(MeasurementItem),
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

/// An expects file containing extendables and standalone expectation items.
/// The phantom `phase` parameter tracks whether the file has been validated.
pub type ExpectsFile(phase) {
  ExpectsFile(
    extendables: List(Extendable),
    items: List(ExpectItem),
    trailing_comments: List(Comment),
  )
}

/// Promotes a MeasurementsFile to a new phantom phase by reconstructing all fields.
@internal
pub fn promote_measurements_file(
  file: MeasurementsFile(a),
) -> MeasurementsFile(b) {
  MeasurementsFile(
    type_aliases: file.type_aliases,
    extendables: file.extendables,
    items: file.items,
    trailing_comments: file.trailing_comments,
  )
}

/// Promotes an ExpectsFile to a new phantom phase by reconstructing all fields.
@internal
pub fn promote_expects_file(file: ExpectsFile(a)) -> ExpectsFile(b) {
  ExpectsFile(
    extendables: file.extendables,
    items: file.items,
    trailing_comments: file.trailing_comments,
  )
}

// =============================================================================
// EXTENDABLES
// =============================================================================

/// An extendable block that can be inherited by measurements or expectations.
pub type Extendable {
  Extendable(
    name: String,
    kind: ExtendableKind,
    body: Struct,
    leading_comments: List(Comment),
  )
}

/// The kind of extendable (Requires for measurement types, Provides for
/// literal-valued field bundles — merged into measurement `Provides {}` or
/// expectation `with: {...}` depending on context).
pub type ExtendableKind {
  ExtendableRequires
  ExtendableProvides
}

/// Converts an extendable kind to its display string.
@internal
pub fn extendable_kind_to_string(kind: ExtendableKind) -> String {
  case kind {
    ExtendableRequires -> "Requires"
    ExtendableProvides -> "Provides"
  }
}

// =============================================================================
// BLUEPRINT NODES
// =============================================================================

/// A single measurement item with name, extends, requires, and provides.
///
/// `expectation_type` carries the declared SLO shape from a header like
/// `"name" success_rate:` or `"name" time_slice:`. When None, the type is
/// inferred from the evaluation formula shape at codegen time (legacy behavior).
pub type MeasurementItem {
  MeasurementItem(
    name: String,
    expectation_type: Option(ExpectationType),
    extends: List(String),
    requires: Struct,
    provides: Struct,
    leading_comments: List(Comment),
  )
}

/// The two surfaced SLO shapes a measurement can declare. Mirrors the CQL
/// resolver's `GoodOverTotal` / `TimeSlice` discriminant, but on the
/// user-visible surface so dependency-edge alignment can be enforced.
pub type ExpectationType {
  SuccessRateType
  TimeSliceType
}

// =============================================================================
// EXPECTS NODES
// =============================================================================

/// A single expectation item. Each item stands alone (no enclosing
/// `Expectations measured by "X"` group).
///
/// An expectation has an optional `Assumes:` section listing dependencies and
/// a required `Guarantees ...` clause carrying threshold, window, optional
/// latency, and an optional `as measured by ... with: {...}` reference.
pub type ExpectItem {
  ExpectItem(
    name: String,
    extends: List(String),
    assumes: Option(Assumes),
    guarantees: Guarantees,
    leading_comments: List(Comment),
  )
}

/// The `Assumes:` section of an expectation. Holds dependency lines.
pub type Assumes {
  Assumes(deps: List(Dependency), trailing_comments: List(Comment))
}

/// A single `hard|soft dependency on "<target>"` line inside Assumes.
pub type Dependency {
  Dependency(
    kind: DependencyKind,
    target: String,
    leading_comments: List(Comment),
  )
}

/// Whether a dependency is hard (participates in threshold math) or soft
/// (tracked in graph only).
pub type DependencyKind {
  HardDep
  SoftDep
}

/// The `Guarantees N% [below D] over D window [as measured by "X" with: {...}]` clause.
pub type Guarantees {
  Guarantees(
    threshold: Float,
    below: Option(DurationLiteral),
    window: DurationLiteral,
    measured_by: Option(MeasuredBy),
  )
}

/// A duration literal value attached to `over`/`below` clauses.
/// Mirrors `ast.LiteralDuration` so the parser can plug the same token into
/// these fixed-position clauses without going through full literal parsing.
pub type DurationLiteral {
  DurationLiteral(amount: Float, unit: String)
}

/// The `as measured by "X" with: {...}` tail of a Guarantees clause.
pub type MeasuredBy {
  MeasuredBy(measurement: String, with_args: Struct)
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

/// A value in a field - either a type (in Requires) or a literal (in Provides).
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
  /// `unit` is the raw suffix as written (one of "ms", "s", "m", "h", "d") so
  /// the formatter can round-trip the source.
  LiteralDuration(amount: Float, unit: String)
  LiteralTrue
  LiteralFalse
  LiteralList(elements: List(Literal))
  LiteralStruct(fields: List(Field), trailing_comments: List(Comment))
  /// An indicator value sourced from a runtime relay (e.g. Langfuse). The
  /// compiler emits both a relay routing entry (in signals.json) and a
  /// vendor metric-query string that consumes the emitted metric. Match
  /// clauses filter source events; `value_extraction` is None for counts
  /// (every matching event is +1) and Some for numeric scores.
  LiteralExternalIndicator(
    source: String,
    match: List(MatchClause),
    value_extraction: Option(ValueExtraction),
  )
}

/// A single `where ... and ...` predicate inside an external-indicator
/// literal. The value is a `Literal` so it round-trips through the formatter
/// and supports `$$var$$` template variables.
pub type MatchClause {
  MatchClause(field: String, value: Literal)
}

/// Optional value-extraction spec on an external indicator. `path` is the
/// dotted path into the source event (e.g. "value" for a Langfuse score's
/// numeric value); `type_` is the declared type/refinement the value must
/// satisfy.
pub type ValueExtraction {
  ValueExtraction(path: String, type_: ParsedType)
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
    LiteralDuration(amount, unit) -> string.inspect(amount) <> unit
    LiteralTrue -> "true"
    LiteralFalse -> "false"
    LiteralList(_) -> "[...]"
    LiteralStruct(_, _) -> "{...}"
    LiteralExternalIndicator(source, _, _) -> "from " <> source <> " {...}"
  }
}
