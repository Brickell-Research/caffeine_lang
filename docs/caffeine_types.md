# Caffeine Type System

Formal type system for Caffeine blueprint parameters.

---

## Type Grammar

```
τ ::= β                              primitives
    | α                              type alias reference
    | List(υ) | Dict(κ, υ)           collections
    | Optional(τ') | Defaulted(τ', v)  modifiers
    | β { x | P(x) }                 refinements (inline)

β ::= String | Integer | Float | Boolean | URL

α ::= _identifier                    type alias (resolves to refined β)

κ ::= β | α                          dict key types (must be string-representable)

υ ::= β | α | List(υ) | Dict(κ, υ)   collection inner types

τ' ::= β | α | List(υ) | Dict(κ, υ)  modifier inner types

P(x) ::= x ∈ S                       (OneOf: S ⊂ β, |S| < ∞)
       | a ≤ x ≤ b                   (InclusiveRange: a, b : β)
```

### Type Alias Definition

```
_name (Type): β { x | P(x) }
```

Type aliases provide named, reusable refined types. They are resolved at compile time
and do not appear in JSON output.

---

## Primitives (β)

| Type | Domain |
|------|--------|
| `String` | Finite sequences of Unicode characters |
| `Integer` | ℤ (arbitrary precision) |
| `Float` | ℝ (IEEE 754 double) |
| `Boolean` | {true, false} |
| `URL` | Valid URL starting with http:// or https:// |

---

## Type Aliases

Type aliases define named, reusable refined types.

**Definition:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_threshold (Type): Float { x | x in ( 0.0..100.0 ) }
_relation (Type): String { x | x in { hard, soft } }
```

**Usage:**
```caffeine
env: _env                           # direct reference
env: Defaulted(_env, "prod")        # with modifier
tags: List(_env)                    # in collection
config: Dict(_env, String)          # as dict key
```

**Resolution:** Type aliases are inlined at compile time:
```
_env → String { x | x in { prod, staging, dev } }
Defaulted(_env, "prod") → Defaulted(String { x | x in { prod, staging, dev } }, prod)
```

---

## Collections

**List(υ)** — Finite sequences [υ]

**Dict(κ, υ)** — Partial functions κ ⇀ υ

Where:
- κ (key type): primitive or type alias
- υ (value type): primitive, type alias, or nested collection

```caffeine
List(String)                    # [String]
List(_env)                      # [refined String]
Dict(String, Integer)           # String ⇀ Integer
Dict(_relation, String)         # refined String ⇀ String
Dict(_relation, List(String))   # refined String ⇀ [String]
Dict(String, Dict(String, Integer))  # nested Dict
```

**Key Constraint:** Dict keys must be string-representable for JSON compatibility.
At validation time, each key in a `Dict(_relation, υ)` is validated against the
type alias's refinement (e.g., must be "hard" or "soft").

---

## Modifiers

Modifiers wrap primitives, type aliases, or collections.

**Optional(τ')** ≡ τ' + Unit

```
Γ ⊢ e : τ'
─────────────────
Γ ⊢ e : Optional(τ')
```

**Defaulted(τ', d)** where d : τ'

```
Γ ⊢ d : τ'
─────────────────────────
Γ ⊢ Defaulted(τ', d) type
```

Semantics: `eval(⊥, Defaulted(τ, d)) = d`

**With Type Aliases:**
```caffeine
Optional(_env)                  # optional refined string
Defaulted(_env, "prod")         # refined string with default
Optional(List(_env))            # optional list of refined strings
Defaulted(Dict(_relation, String), {})  # dict with refined keys, default empty
```

**Default Value Validation:** When using `Defaulted(_alias, default)`, the default
value is validated against the type alias's refinement at JSON parse time (not
Caffeine parse time). For example, `Defaulted(_env, "invalid")` would fail
validation because "invalid" is not in `{ prod, staging, dev }`.

---

## Refinements

### OneOf

```
{ x : τ | x ∈ S }  where S ⊂ τ, |S| < ∞
```

Supported base types: `String | Integer | Float | Defaulted(String|Integer|Float, _)`

```caffeine
String { x | x in { "datadog", "prometheus" } }
Integer { x | x in { 7, 30, 90 } }
Defaulted(Integer, 30) { x | x in { 7, 30, 90 } }
```

### InclusiveRange

```
{ x : τ | a ≤ x ≤ b }  where a, b : τ, a ≤ b
```

Supported base types: `Integer | Float`

```caffeine
Float { x | x in ( 0.0..100.0 ) }
Integer { x | x in ( 1..365 ) }
```

---

## Subtyping

```
τ <: τ                                    (reflexivity)

{ x : τ | P(x) } <: τ                     (refinement weakening)

{ x : τ | P(x) ∧ Q(x) } <: { x : τ | P(x) }  (predicate weakening)

α <: β  where α resolves to β { x | P(x) }  (type alias weakening)
```

---

## Resolution Order

Type aliases are resolved before extendables during compilation:

1. **Parse type aliases** — Build lookup table of `_name → refined type`
2. **Resolve aliases in extendables** — Replace `_name` references with their definitions
3. **Resolve aliases in blueprints/expects** — Replace remaining references
4. **Merge extendables** — Inline extendable fields (existing behavior)
5. **Output JSON** — All type aliases are fully inlined

**Example:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_common (Requires): { env: Defaulted(_env, "prod") }

Blueprints for "SLO"
  * "api" extends [_common]:
    Requires { threshold: Float }
```

After resolution:
```json
{
  "params": {
    "env": "Defaulted(String { x | x in { prod, staging, dev } }, prod)",
    "threshold": "Float"
  }
}
```
