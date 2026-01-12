# Caffeine Type System

Formal type system for Caffeine blueprint parameters.

---

## Type Grammar

```
τ ::= β                              primitives
    | List(β) | Dict(β, β)           collections
    | Optional(τ') | Defaulted(τ', v)  modifiers
    | { x : τ'' | P(x) }             refinements

β ::= String | Integer | Float | Boolean

τ' ::= β | List(β) | Dict(β, β)

τ'' ::= β | Defaulted(β, v)          (for OneOf)
      | Integer | Float               (for InclusiveRange)
```

---

## Primitives (β)

| Type | Domain |
|------|--------|
| `String` | Finite sequences of Unicode characters |
| `Integer` | ℤ (arbitrary precision) |
| `Float` | ℝ (IEEE 754 double) |
| `Boolean` | {true, false} |

---

## Collections

**List(β)** — Finite sequences [β]

**Dict(β₁, β₂)** — Partial functions β₁ ⇀ β₂

```caffeine
List(String)           # [String]
Dict(String, Integer)  # String ⇀ Integer
```

---

## Modifiers

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
```
