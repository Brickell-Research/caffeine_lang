# Caffeine Language Specification

**Version:** 0.1.0 (Draft)

---

## Terminology

| Term | Definition |
|------|------------|
| **Artifact** | A base schema defining what parameters exist and their types. Artifacts live in the compiler's standard library and cannot be defined by users. Example: an `SLO` artifact defines that all SLOs need a threshold, window, and queries. |
| **Blueprint** | A partially-configured artifact. Blueprints fix some values and declare which parameters users must provide. Defined in `blueprints.caffeine`. Example: an `api_availability` blueprint might fix the query structure but require users to specify `env` and `threshold`. |
| **Expectation** | A fully-configured blueprint with all required values provided. Defined in `expectations/**/*.caffeine`. Example: `checkout_availability` extends `api_availability` and provides `env: "production"`, `threshold: 99.95`. |
| **Extendable** | A reusable block of values (prefixed with `_`) that can be inherited by blueprints or expectations to reduce repetition. |
| **Type Alias** | A named, reusable refined type (prefixed with `_`) that can be referenced in type positions. Inlined at compile time. |

---

## Design Principles

Caffeine is guided by these core principles:

| Principle | Description |
|-----------|-------------|
| **One way to do things** | Single canonical syntax for each concept. No alternative forms or shortcuts. |
| **Explicit over implicit** | All behavior is visible in the code. No hidden defaults or magic. |
| **Readable at a glance** | SREs should understand configs without deep language knowledge. |
| **Fail early, fail clearly** | Catch errors at compile time with precise source locations and suggestions. |
| **Domain-specific vocabulary** | Use SLO/reliability terminology, not generic programming constructs. |

---

## Three-Tier Hierarchy

| Tier | Location | Purpose |
|------|----------|---------|
| **Artifact** | stdlib (compiler-internal) | Base schema with typed parameters |
| **Blueprint** | `blueprints.caffeine` | Partially instantiated artifact |
| **Expectation** | `expectations/**/*.caffeine` | Fully instantiated blueprint |

**Note:** Artifacts are defined exclusively in the compiler's stdlib and are not part of the user-facing DSL. Users reference artifacts by name in `Blueprints for "<ArtifactName>"` but cannot define new artifacts.

---

## Notation

This specification uses the following conventions:

| Notation | Meaning |
|----------|---------|
| `literal` | Exact literal text |
| `<name>` | Non-terminal (defined elsewhere) |
| `[ ]` | Optional |
| `{ }` | Zero or more repetitions |
| `( )` | Grouping |
| `\|` | Alternation (or) |
| `"text"` | Literal string |
| `UPPER` | Token class (e.g., STRING, INTEGER) |

---

## BNF Grammar

**Notes:**
- Artifacts are defined in the compiler stdlib only and are not part of this grammar
- A file contains **either** blueprints **or** expectations, never both

```bnf
# A file contains EITHER blueprints OR expectations, never both
<file>              ::= <blueprints_file> | <expects_file>

<blueprints_file>   ::= { <type_alias> } { <blueprint_extendable> } <blueprints_block> { <blueprints_block> }

<expects_file>      ::= { <expects_extendable> } <expects_block> { <expects_block> }

<type_alias>           ::= "_" IDENTIFIER "(Type)" ":" <refinement_type>

<blueprint_extendable> ::= "_" IDENTIFIER ( "(Requires)" | "(Provides)" ) ":" <struct>

<expects_extendable>   ::= "_" IDENTIFIER "(Provides)" ":" <struct>

<blueprints_block>  ::= "Blueprints" "for" <artifact_list> <newline>
                        { <blueprint_item> }

<artifact_list>     ::= STRING { "+" STRING }

<expects_block>     ::= "Expects" "for" STRING <newline>
                        { <expect_item> }

<blueprint_item>    ::= "*" STRING [ "extends" <extend_list> ] ":" <newline>
                        <indent> <requires_line>
                        <indent> <provides_line>

<expect_item>       ::= "*" STRING [ "extends" <extend_list> ] ":" <newline>
                        <indent> <provides_line>

<extend_list>       ::= "[" IDENTIFIER { "," IDENTIFIER } "]"

<requires_line>     ::= "Requires" <struct>

<provides_line>     ::= "Provides" <struct>

<struct>            ::= "{" [ <field_list> ] "}"

<field_list>        ::= <field> { "," <field> } [ "," ]

<field>             ::= IDENTIFIER ":" <value>

<value>             ::= <literal> | <type> | <struct>

<literal>           ::= STRING | NUMBER | BOOLEAN | <list> | <struct>

<list>              ::= "[" [ <literal> { "," <literal> } ] "]"

<type>              ::= <primitive_type>
                      | <type_alias_ref>
                      | <collection_type>
                      | <modifier_type>
                      | <refinement_type>

<primitive_type>    ::= "String" | "Integer" | "Float" | "Boolean" | "URL"

# Type alias reference: refers to a previously defined type alias
<type_alias_ref>    ::= "_" IDENTIFIER

# Collections: inner types can be primitives, type aliases, or nested collections
<collection_type>   ::= "List" "(" <collection_inner> ")"
                      | "Dict" "(" <dict_key_type> "," <collection_inner> ")"

<dict_key_type>     ::= <primitive_type> | <type_alias_ref>

<collection_inner>  ::= <primitive_type> | <type_alias_ref> | <collection_type>

# Modifiers: inner types can be primitives, type aliases, or collections
<modifier_type>     ::= "Optional" "(" <modifier_inner> ")"
                      | "Defaulted" "(" <modifier_inner> "," <default_value> ")"

<modifier_inner>    ::= <primitive_type> | <type_alias_ref> | <collection_type>

<refinement_type>   ::= <oneof_type> | <range_type>

# OneOf: supports String, Integer, Float (not Boolean), and Defaulted variants
<oneof_type>        ::= <oneof_inner> "{" "x" "|" "x" "in" "{" <oneof_value> { "," <oneof_value> } "}" "}"

<oneof_inner>       ::= "String" | "Integer" | "Float"
                      | "Defaulted" "(" <oneof_inner> "," <default_value> ")"

<oneof_value>       ::= STRING | NUMBER

# InclusiveRange: supports Integer, Float only (not Defaulted)
<range_type>        ::= <range_inner> "{" "x" "|" "x" "in" "(" NUMBER ".." NUMBER ")" "}"

<range_inner>       ::= "Integer" | "Float"

<default_value>     ::= NUMBER | STRING

<comment>           ::= "#" TEXT <newline>

# Tokens
STRING              ::= '"' { CHARACTER } '"'
IDENTIFIER          ::= ( LETTER | "_" ) { LETTER | DIGIT | "_" }
NUMBER              ::= INTEGER | FLOAT
INTEGER             ::= [ "-" ] DIGIT { DIGIT }
FLOAT               ::= [ "-" ] DIGIT { DIGIT } "." DIGIT { DIGIT }
BOOLEAN             ::= "true" | "false"

# Whitespace and structure
<newline>           ::= "\n" | "\r\n"
<indent>            ::= "  " | "\t"

# Character classes
LETTER              ::= "a".."z" | "A".."Z"
DIGIT               ::= "0".."9"
CHARACTER           ::= <any Unicode character except '"' and newline>
TEXT                ::= { <any character except newline> }
```

---

## Lexical Elements

### Comments

```caffeine
# Single-line comment
```

### Literals

```caffeine
"string"      # double quotes only, single line
42            # integer
3.14          # float
true false    # bool
[1, 2, 3]     # list
{a: 1}        # dict (keys are always strings, no quotes needed)
```

---

## Types

See [Type System](caffeine_types.md) for detailed type documentation with examples.

---

## Errors

See [Errors](caffeine_errors.md) for error categories and message format.

---

## Type Aliases

Reusable refined types that can be referenced in type positions.

**Rules:**
- Must start with `_` prefix
- Must specify kind: `(Type)`
- Must be at top of file (before extendables and blocks)
- File-scoped only (cannot reference across files)
- Can only alias refined primitive types (no chaining/inheritance)
- Inlined at compile time (do not appear in JSON output)

**Definition:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_vendor (Type): String { x | x in { datadog, prometheus } }
_threshold (Type): Float { x | x in ( 0.0..100.0 ) }
_window (Type): Integer { x | x in { 7, 30, 90 } }
_relation (Type): String { x | x in { hard, soft } }
```

**Usage in Types:**
```caffeine
# Direct usage
env: _env

# With modifiers
env: Defaulted(_env, "prod")
env: Optional(_env)

# In collections
tags: List(_env)
config: Dict(_env, String)
dependencies: Dict(_relation, List(String))
```

**Usage in Extendables:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_common (Requires): { env: Defaulted(_env, "prod"), vendor: _vendor }
```

**Compilation:**
Type aliases are fully inlined during compilation. For example:

```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
Requires { env: Defaulted(_env, "prod") }
```

Compiles to JSON as:
```json
{
  "params": {
    "env": "Defaulted(String { x | x in { prod, staging, dev } }, prod)"
  }
}
```

---

## Extendables

Reusable value blocks that can be extended by blueprints or expectations.

**Rules:**
- Must start with `_` prefix
- Must specify kind: `(Requires)` for type definitions, `(Provides)` for value definitions
- Must appear after type aliases but before any `Blueprints for` or `Expects for`
- File-scoped only (cannot reference across files)
- Can reference type aliases defined in the same file

**In Blueprints:**
```caffeine
_common (Requires): { env: String, status: Boolean }
_base_slo (Provides): { vendor: "datadog" }
```

**In Expectations:**
```caffeine
_defaults (Provides): { env: "production", window_in_days: 30 }
_strict (Provides): { threshold: 99.99, window_in_days: 7 }
```

**Note:** Expectations only use `(Provides)` extendables since they only provide values, never types.

---

## Blueprints

### Single Artifact

```caffeine
Blueprints for "<ArtifactName>"
  * "<blueprint_name>":
    Requires { <required_params> }
    Provides { <provided_values> }
```

### Multi-Artifact

A blueprint can implement multiple artifacts using `+`. Params from all artifacts are merged.

```caffeine
Blueprints for "<Artifact1>" + "<Artifact2>"
  * "<blueprint_name>":
    Requires { <params_from_both_artifacts> }
    Provides { <values_for_both_artifacts> }
```

**Structure:**
- `* "name":` or `* "name" extends [...]:` on its own line
- `Requires` and `Provides` lines must be indented below the name line
- `Requires` declares params expectations must provide (types only)
- `Provides` declares values the blueprint fixes (values only)
- For multi-artifact, params must not conflict across artifacts

---

## Expectations

```caffeine
Expects for "<BlueprintName>"
  ## Section Header
  * "<expectation_name>":
    Provides { <values> }

  * "<expectation_name>" extends [_extendable, ...]:
    Provides { <values> }
```

**Structure:**
- `* "name":` or `* "name" extends [...]:` on its own line
- `Provides` line must be indented below the name line
- `Provides` provides all remaining required values

---

## Expectation References

Some artifacts (like `DependencyRelation`) have params that reference other expectations. References use the format:

```
ORG_DIRECTORY.TEAM_NAME.SERVICE_NAME.EXPECTATION_NAME
```

**Examples:**

```caffeine
Provides {
  relations: {
    hard: ["acme.payments.checkout.payment_availability"],
    soft: ["acme.recommendations.main.recs_availability"]
  }
}
```

**Validation:**
- References are validated at compile time
- Circular dependencies are rejected by the compiler

---

## Template Variables

Used in blueprint query strings for value interpolation.

```caffeine
$$var$$             # raw value: inserts value directly
$$var->attr$$       # key-value: produces attr:value
$$var->attr:not$$   # negated: produces !attr:value
```

**Examples:**

```caffeine
"sum:requests{$$env->env$$, $$status->status:not$$}"    # env:production, !status:true
"threshold < $$threshold$$"                             # threshold < 99.9
"service:$$service->service$$"                          # service:checkout
```

When variable and attribute names differ:

```caffeine
$$environment->env$$    # variable 'environment', produces attr 'env'
```

---

## Keywords Summary

| Keyword | Meaning | Used In |
|---------|---------|---------|
| `Requires` | Params needed from expectations (types only) | Blueprints only |
| `Provides` | Values given (literals only) | Blueprints & Expectations |

---

## Full Example

### blueprints.caffeine

```caffeine
# Type Aliases
_env (Type): String { x | x in { prod, staging, dev } }
_threshold (Type): Float { x | x in ( 0.0..100.0 ) }
_window (Type): Integer { x | x in { 7, 30, 90 } }
_relation (Type): String { x | x in { hard, soft } }

# Extendables
_base_slo (Provides): { vendor: "datadog" }
_common (Requires): { env: Defaulted(_env, "prod"), window_in_days: Defaulted(_window, 30) }

Blueprints for "SLO"
  ## API Availability
  * "api_availability" extends [_base_slo, _common]:
    Requires {
      status: Boolean,
      threshold: _threshold
    }
    Provides {
      value: "numerator / denominator",
      queries: {
        numerator: "sum:http.requests{$$env->env$$, $$status->status:not$$}",
        denominator: "sum:http.requests{$$env->env$$}"
      }
    }

  ## Latency
  * "latency" extends [_common]:
    Requires {
      service: String,
      threshold_ms: Integer,
      threshold: _threshold
    }
    Provides {
      vendor: "datadog",
      value: "time_slice(latency < $$threshold_ms$$ per 5m)",
      queries: {
        latency: "avg:http.latency{$$env->env$$, $$service->service$$}"
      }
    }

  ## Service with Dependencies
  * "service_with_deps" extends [_base_slo, _common]:
    Requires {
      status: Boolean,
      threshold: _threshold,
      dependencies: Dict(_relation, List(String))
    }
    Provides {
      value: "numerator / denominator",
      queries: {
        numerator: "sum:http.requests{$$env->env$$, $$status->status:not$$}",
        denominator: "sum:http.requests{$$env->env$$}"
      }
    }

Blueprints for "DependencyRelation"
  ## Hard Dependency
  * "hard_dependency":
    Requires { from: String, to: String }
    Provides { type: "hard", error_budget_share: 0.5 }

  ## Soft Dependency
  * "soft_dependency":
    Requires { from: String, to: String }
    Provides { type: "soft", error_budget_share: 0.1 }

Blueprints for "SLO" + "DependencyRelation"
  ## SLO with Upstream Tracking
  * "tracked_slo" extends [_base_slo]:
    Requires {
      env: String,
      status: Boolean,
      upstream: String,
      threshold: Float { x | x in ( 0.0..100.0 ) },
      window_in_days: Integer
    }
    Provides {
      value: "numerator / denominator",
      queries: {
        numerator: "sum:http.requests{$$env->env$$, $$status->status:not$$}",
        denominator: "sum:http.requests{$$env->env$$}"
      },
      type: "hard"
    }
```

### expectations/acme/payments/checkout.caffeine

```caffeine
# Extendables
_defaults (Provides): { env: "production", window_in_days: 30 }
_strict (Provides): { window_in_days: 7, threshold: 99.99 }

Expects for "api_availability"
  ## Core Services
  * "checkout_availability" extends [_defaults]:
    Provides { threshold: 99.95, status: true }

  * "payment_availability" extends [_defaults]:
    Provides { threshold: 99.99, status: true }

  * "inventory_availability" extends [_defaults]:
    Provides { threshold: 99.9, status: true }

Expects for "latency"
  ## Response Times
  * "checkout_p99" extends [_defaults]:
    Provides { threshold: 99.0, service: "checkout", threshold_ms: 500 }

Expects for "tracked_slo"
  ## Frontend with Upstream Awareness
  * "frontend_availability" extends [_defaults]:
    Provides {
      threshold: 99.9,
      status: true,
      relations: {
        hard: ["acme.payments.checkout.checkout_availability"]
      }
    }
```

---

## JSON Output

### Single-Artifact Blueprint

Type aliases are fully inlined in JSON output:

```json
{
  "name": "api_availability",
  "artifact_refs": ["SLO"],
  "params": {
    "env": "Defaulted(String { x | x in { prod, staging, dev } }, prod)",
    "window_in_days": "Defaulted(Integer { x | x in { 7, 30, 90 } }, 30)",
    "status": "Boolean",
    "threshold": "Float { x | x in ( 0.0..100.0 ) }"
  },
  "inputs": {
    "vendor": "datadog",
    "value": "numerator / denominator",
    "queries": {
      "numerator": "sum:http.requests{$$env->env$$, $$status->status:not$$}",
      "denominator": "sum:http.requests{$$env->env$$}"
    }
  }
}
```

### Blueprint with Dict Type Alias Keys

```json
{
  "name": "service_with_deps",
  "artifact_refs": ["SLO"],
  "params": {
    "env": "Defaulted(String { x | x in { prod, staging, dev } }, prod)",
    "window_in_days": "Defaulted(Integer { x | x in { 7, 30, 90 } }, 30)",
    "status": "Boolean",
    "threshold": "Float { x | x in ( 0.0..100.0 ) }",
    "dependencies": "Dict(String { x | x in { hard, soft } }, List(String))"
  },
  "inputs": {
    "vendor": "datadog",
    "value": "numerator / denominator",
    "queries": { ... }
  }
}
```

### Multi-Artifact Blueprint

```json
{
  "name": "tracked_slo",
  "artifact_refs": ["SLO", "DependencyRelation"],
  "params": {
    "env": "String",
    "status": "Boolean",
    "upstream": "String",
    "threshold": "Float { x | x in ( 0.0..100.0 ) }",
    "window_in_days": "Integer"
  },
  "inputs": {
    "vendor": "datadog",
    "value": "numerator / denominator",
    "queries": { ... },
    "type": "hard"
  }
}
```

### Expectation

```json
{
  "name": "checkout_availability",
  "blueprint_ref": "api_availability",
  "inputs": {
    "threshold": 99.95,
    "window_in_days": 30,
    "env": "production",
    "status": true
  }
}
```

### Expectation with Dependencies

```json
{
  "name": "frontend_availability",
  "blueprint_ref": "tracked_slo",
  "inputs": {
    "threshold": 99.9,
    "status": true,
    "relations": {
      "hard": ["acme.payments.checkout.checkout_availability"]
    }
  }
}
```

---

## Internals

See [Internals](caffeine_internals.md) for details on how Caffeine compiles to JSON (extendable inlining, merge order).

---

## Future

| Feature | Description |
|---------|-------------|
| **IDE/LSP support** | Language server for autocomplete, validation, and hover documentation |
| **Dependency visualization** | `caffeine graph` command to visualize expectation dependencies |
