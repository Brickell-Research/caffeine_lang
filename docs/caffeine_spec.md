# Caffeine Language Specification

**Version:** 5.0.4

---

## Terminology

| Term | Definition |
|------|------------|
| **Measurement** | A reusable SLO template that declares required parameters and provides query structure. Defined in measurement files (e.g., `datadog.caffeine`). Replaces the former "Blueprint" concept. |
| **Expectation** | A fully-configured SLO instance. Can be "measured" (backed by a measurement) or "unmeasured" (standalone with minimal fields). Defined in expectation files (`expectations/**/*.caffeine`). |
| **Extendable** | A reusable block of values (prefixed with `_`) that can be inherited by measurements or expectations to reduce repetition. |
| **Type Alias** | A named, reusable refined type (prefixed with `_`) that can be referenced in type positions. Inlined at compile time. |
| **Vendor** | The observability platform. Derived from the measurement filename (e.g., `datadog.caffeine` implies Datadog). Supported: Datadog, Honeycomb, Dynatrace, NewRelic. |

---

## Design Principles

| Principle | Description |
|-----------|-------------|
| **One way to do things** | Single canonical syntax for each concept. No alternative forms or shortcuts. |
| **Explicit over implicit** | All behavior is visible in the code. No hidden defaults or magic. |
| **Readable at a glance** | SREs should understand configs without deep language knowledge. |
| **Fail early, fail clearly** | Catch errors at compile time with precise source locations and suggestions. |
| **Domain-specific vocabulary** | Use SLO/reliability terminology, not generic programming constructs. |

---

## Two File Types

| File Type | Purpose | Example Filename |
|-----------|---------|------------------|
| **Measurements** | SLO templates with required params and query definitions | `datadog.caffeine`, `honeycomb.caffeine` |
| **Expectations** | Concrete SLO instances referencing measurements | `expectations/acme/payments/checkout.caffeine` |

The vendor is derived from the measurement filename. A file contains **either** measurements **or** expectations, never both.

---

## Notation

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

```bnf
# A file contains EITHER measurements OR expectations, never both
<file>                  ::= <measurements_file> | <expects_file>

# ---- Measurements File ----

<measurements_file>     ::= { <type_alias> }
                            { <measurement_extendable> }
                            { <measurement_item> }

<type_alias>            ::= "_" IDENTIFIER "(Type)" ":" <refinement_type>

<measurement_extendable> ::= "_" IDENTIFIER ( "(Requires)" | "(Provides)" ) ":" <struct>

<measurement_item>      ::= STRING ":" <newline>
                            <indent> [ "extends" <extend_list> <newline> ]
                            <indent> <requires_line> <newline>
                            <indent> <provides_line>

# ---- Expectations File ----

<expects_file>          ::= { <expects_extendable> }
                            { <expects_block> }

<expects_extendable>    ::= "_" IDENTIFIER "(Provides)" ":" <struct>

<expects_block>         ::= <measured_block> | <unmeasured_block>

<measured_block>        ::= "Expectations" "measured" "by" STRING <newline>
                            { <expect_item> }

<unmeasured_block>      ::= "Unmeasured" "Expectations" <newline>
                            { <expect_item> }

<expect_item>           ::= "*" STRING [ "extends" <extend_list> ] ":" <newline>
                            <indent> <provides_line>

# ---- Shared Grammar ----

<extend_list>           ::= "[" IDENTIFIER { "," IDENTIFIER } "]"

<requires_line>         ::= "Requires" <struct>

<provides_line>         ::= "Provides" <struct>

<struct>                ::= "{" [ <field_list> ] "}"

<field_list>            ::= <field> { "," <field> } [ "," ]

<field>                 ::= IDENTIFIER ":" <value>

<value>                 ::= <literal> | <type> | <struct>

<literal>               ::= STRING | NUMBER | PERCENTAGE | BOOLEAN | <list> | <struct>

<list>                  ::= "[" [ <literal> { "," <literal> } ] "]"

<type>                  ::= <primitive_type>
                          | <type_alias_ref>
                          | <collection_type>
                          | <modifier_type>
                          | <refinement_type>

<primitive_type>        ::= "String" | "Integer" | "Float" | "Boolean" | "URL"

# Type alias reference: refers to a previously defined type alias
<type_alias_ref>        ::= "_" IDENTIFIER

# Collections: inner types can be primitives, type aliases, or nested collections
<collection_type>       ::= "List" "(" <collection_inner> ")"
                          | "Dict" "(" <dict_key_type> "," <collection_inner> ")"

<dict_key_type>         ::= <primitive_type> | <type_alias_ref>

<collection_inner>      ::= <primitive_type> | <type_alias_ref> | <collection_type>

# Modifiers: inner types can be primitives, type aliases, or collections
<modifier_type>         ::= "Optional" "(" <modifier_inner> ")"
                          | "Defaulted" "(" <modifier_inner> "," <default_value> ")"

<modifier_inner>        ::= <primitive_type> | <type_alias_ref> | <collection_type>

<refinement_type>       ::= <oneof_type> | <range_type>

# OneOf: supports String, Integer, Float (not Boolean), and Defaulted variants
<oneof_type>            ::= <oneof_inner> "{" "x" "|" "x" "in" "{" <oneof_value> { "," <oneof_value> } "}" "}"

<oneof_inner>           ::= "String" | "Integer" | "Float"
                          | "Defaulted" "(" <oneof_inner> "," <default_value> ")"

<oneof_value>           ::= STRING | NUMBER

# InclusiveRange: supports Integer, Float only (not Defaulted)
<range_type>            ::= <range_inner> "{" "x" "|" "x" "in" "(" NUMBER ".." NUMBER ")" "}"

<range_inner>           ::= "Integer" | "Float"

<default_value>         ::= NUMBER | STRING | PERCENTAGE

<comment>               ::= "#" TEXT <newline>
<section_comment>       ::= "##" TEXT <newline>

# Tokens
STRING                  ::= '"' { CHARACTER } '"'
IDENTIFIER              ::= ( LETTER | "_" ) { LETTER | DIGIT | "_" }
NUMBER                  ::= INTEGER | FLOAT
INTEGER                 ::= [ "-" ] DIGIT { DIGIT }
FLOAT                   ::= [ "-" ] DIGIT { DIGIT } "." DIGIT { DIGIT }
PERCENTAGE              ::= FLOAT "%"
BOOLEAN                 ::= "true" | "false"

# Whitespace and structure
<newline>               ::= "\n" | "\r\n"
<indent>                ::= "  " | "\t"

# Character classes
LETTER                  ::= "a".."z" | "A".."Z"
DIGIT                   ::= "0".."9"
CHARACTER               ::= <any Unicode character except '"' and newline>
TEXT                    ::= { <any character except newline> }
```

---

## Lexical Elements

### Comments

```caffeine
# Single-line comment
## Section header comment
```

### Literals

```caffeine
"string"        # double quotes only, single line
42              # integer
3.14            # float
99.9%           # percentage (used for thresholds)
true false      # bool
[1, 2, 3]       # list
{a: 1}          # struct (keys are unquoted identifiers)
```

---

## Types

See [Type System](caffeine_types.md) for detailed type documentation with examples.

---

## Errors

See [Errors](caffeine_errors.md) for error categories and message format.

---

## SLO Parameters

Every SLO (measured or unmeasured) has these built-in parameters:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `threshold` | Percentage | Yes | -- | SLO target (e.g., `99.9%`) |
| `window_in_days` | Integer (1-90) | No | `30` | Rolling window for SLO evaluation |
| `evaluation` | String | Measured only | -- | Formula referencing indicator names (e.g., `"numerator / denominator"`) |
| `indicators` | Dict(String, String) | Measured only | -- | Named query strings for the vendor |
| `tags` | Optional Dict(String, String) | No | -- | User-defined tags on the SLO resource |
| `runbook` | Optional URL | No | -- | Link to operational runbook |
| `depends_on` | Optional Record | No | -- | Dependency references (see below) |

**Unmeasured expectations** may only provide: `threshold`, `window_in_days`, and `depends_on`.

---

## Type Aliases

Reusable refined types that can be referenced in type positions.

**Rules:**
- Must start with `_` prefix
- Must specify kind: `(Type)`
- Must be at top of file (before extendables and items/blocks)
- File-scoped only (cannot reference across files)
- Can only alias refined primitive types (no chaining/inheritance)
- Inlined at compile time

**Definition:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_threshold (Type): Float { x | x in ( 0.0..100.0 ) }
_window (Type): Integer { x | x in { 7, 30, 90 } }
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
```

**Usage in Extendables:**
```caffeine
_env (Type): String { x | x in { prod, staging, dev } }
_common (Requires): { env: Defaulted(_env, "prod") }
```

---

## Extendables

Reusable value blocks that can be inherited by measurements or expectations.

**Rules:**
- Must start with `_` prefix
- Must specify kind: `(Requires)` for type definitions, `(Provides)` for value definitions
- Must appear after type aliases but before measurement items or expectation blocks
- File-scoped only (cannot reference across files)
- Can reference type aliases defined in the same file

**In Measurements:**
```caffeine
_common (Requires): { env: String, status: Boolean }
_base_slo (Provides): { threshold: 99.9% }
```

**In Expectations:**
```caffeine
_defaults (Provides): { env: "production", window_in_days: 30 }
_strict (Provides): { threshold: 99.99%, window_in_days: 7 }
```

**Note:** Expectations only use `(Provides)` extendables since they only provide values, never types.

---

## Measurements

Measurements are SLO templates defined at the top level of a measurement file. Each measurement has a name, an optional `extends` clause, a `Requires` block (parameter types), and a `Provides` block (fixed values including query structure).

```caffeine
"<measurement_name>":
  Requires { <required_params> }
  Provides { <provided_values> }
```

With extends:

```caffeine
"<measurement_name>":
  extends [_extendable, ...]
  Requires { <required_params> }
  Provides { <provided_values> }
```

**Structure:**
- Items are top-level (no header block, no `*` bullet prefix)
- Name on its own line, followed by a colon
- Optional `extends` clause on the next indented line
- `Requires` and `Provides` lines are indented below the name
- `Requires` declares params that expectations must provide (types only)
- `Provides` declares values the measurement fixes (values only)
- `evaluation` and `indicators` are provided within the `Provides` block

**Vendor resolution:** The vendor is determined by the measurement filename:
- `datadog.caffeine` -- Datadog
- `honeycomb.caffeine` -- Honeycomb
- `dynatrace.caffeine` -- Dynatrace
- `newrelic.caffeine` -- NewRelic

---

## Expectations

Expectations are concrete SLO instances. They come in two forms:

### Measured Expectations

Backed by a measurement template. The measurement provides query structure; the expectation fills in parameter values.

```caffeine
Expectations measured by "<measurement_name>"
  * "<expectation_name>":
    Provides { <values> }

  * "<expectation_name>" extends [_extendable, ...]:
    Provides { <values> }
```

### Unmeasured Expectations

Standalone SLOs with no measurement backing. Only `threshold`, `window_in_days`, and `depends_on` are permitted.

```caffeine
Unmeasured Expectations
  * "<expectation_name>":
    Provides { threshold: 99.5%, window_in_days: 30 }
```

**Structure:**
- Blocks start with `Expectations measured by "<name>"` or `Unmeasured Expectations`
- Items are prefixed with `*`
- `* "name":` or `* "name" extends [...]:` on its own line
- `Provides` line must be indented below the name line
- Section comments (`##`) can be used within blocks

---

## Dependencies

Dependencies between SLOs are declared via the `depends_on` field. Both `hard` and `soft` lists are optional within the record.

```caffeine
depends_on: {
  hard: ["org.team.service.name"],
  soft: ["org.team.service.name"]
}
```

**Reference format:**
```
ORG_DIRECTORY.TEAM_NAME.SERVICE_NAME.EXPECTATION_NAME
```

**Validation:**
- All referenced targets must exist in the compiled expectation set
- Circular dependency chains are rejected
- Hard dependency threshold ceiling: a hard dependency's threshold cannot exceed its dependent's threshold

**Examples:**

```caffeine
# Hard dependencies only
depends_on: { hard: ["acme.payments.checkout.payment_availability"] }

# Soft dependencies only
depends_on: { soft: ["acme.recommendations.main.recs_availability"] }

# Both
depends_on: {
  hard: ["acme.payments.checkout.payment_availability"],
  soft: ["acme.recommendations.main.recs_availability"]
}
```

---

## Template Variables

Used in measurement indicator query strings for value interpolation at compile time.

```caffeine
$$var$$                 # raw value: inserts value directly
$$var->attr$$           # key-value: produces attr:value
$$var->attr:not$$       # negated: produces !attr:value
```

**Delimiter:** Template variables are enclosed in `$...$` pairs within query strings.

**Examples:**

```caffeine
# In a measurement's indicators
indicators: {
  numerator: "sum:http.requests{$env->env$, $status->status:not$}",
  denominator: "sum:http.requests{$env->env$}"
}

# Raw substitution
"threshold < $$threshold$$"           # threshold < 99.9

# Different variable and attribute names
"$$environment->env$$"                # variable 'environment', produces attr 'env'
```

When an expectation provides `env: "production"` and `status: "5xx"`:
- `$env->env$` resolves to `env:production`
- `$status->status:not$` resolves to `!status:5xx`

For list values, key-value templates produce `IN` syntax:
- `$env->env$` with `env: ["prod", "staging"]` resolves to `env IN (prod, staging)`

---

## Keywords Summary

| Keyword | Meaning | Used In |
|---------|---------|---------|
| `Requires` | Params needed from expectations (types only) | Measurements only |
| `Provides` | Values given (literals only) | Measurements and Expectations |
| `extends` | Inherit from extendables | Measurements and Expectations |
| `Expectations measured by` | Block header referencing a measurement | Expectations files |
| `Unmeasured Expectations` | Block header for standalone SLOs | Expectations files |

---

## Full Example

### datadog.caffeine (Measurements File)

```caffeine
# Type Aliases
_env (Type): String { x | x in { prod, staging, dev } }

# Extendables
_common (Requires): { env: Defaulted(_env, "prod") }
_defaults (Provides): { threshold: 99.9% }

## API Availability
"api_availability":
  extends [_common]
  Requires {
    status: Boolean
  }
  Provides {
    threshold: 99.9%,
    evaluation: "numerator / denominator",
    indicators: {
      numerator: "sum:http.requests{$env->env$, $status->status:not$}",
      denominator: "sum:http.requests{$env->env$}"
    }
  }

## Latency
"latency":
  extends [_common]
  Requires {
    service: String,
    threshold_ms: Integer
  }
  Provides {
    threshold: 99.0%,
    evaluation: "time_slice(latency < $$threshold_ms$$ per 5m)",
    indicators: {
      latency: "avg:http.latency{$env->env$, $service->service$}"
    }
  }
```

### expectations/acme/payments/checkout.caffeine (Expectations File)

```caffeine
# Extendables
_defaults (Provides): { env: "production" }
_strict (Provides): { threshold: 99.99%, window_in_days: 7 }

Expectations measured by "api_availability"
  ## Core Services
  * "checkout_availability" extends [_defaults]:
    Provides { threshold: 99.95%, status: true }

  * "payment_availability" extends [_defaults]:
    Provides { threshold: 99.99%, status: true }

  * "inventory_availability" extends [_defaults]:
    Provides { threshold: 99.9%, status: true }

Expectations measured by "latency"
  ## Response Times
  * "checkout_p99" extends [_defaults]:
    Provides { threshold: 99.0%, service: "checkout", threshold_ms: 500 }

Unmeasured Expectations
  ## Third-Party Dependencies
  * "third_party_gateway":
    Provides { threshold: 99.5%, window_in_days: 30 }

  * "cdn_availability":
    Provides {
      threshold: 99.9%,
      depends_on: {
        hard: ["acme.payments.checkout.checkout_availability"],
        soft: ["acme.payments.checkout.inventory_availability"]
      }
    }
```

---

## Compilation Output

Caffeine compiles to Terraform HCL targeting vendor-specific SLO resources. The output includes:

- **Terraform resources**: One `datadog_service_level_objective` (or equivalent) per expectation
- **Provider configuration**: Vendor-specific provider and variable blocks
- **Dependency graph**: DOT-format graph of SLO dependency relationships
- **Warnings**: Non-fatal issues (e.g., tag overshadowing)

Template variables in indicator queries are resolved at compile time by substituting expectation values into measurement query templates.

---

## Internals

See [Internals](caffeine_internals.md) for details on compilation pipeline (extendable inlining, merge order, vendor resolution).
