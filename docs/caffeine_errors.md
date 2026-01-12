# Caffeine Errors

Caffeine follows the "fail early, fail clearly" principle. All errors include source locations and actionable context.

---

## Error Categories

| Category | Phase | Description |
|----------|-------|-------------|
| **Parse** | Parsing | Syntax errors, malformed structures |
| **Resolve** | Linking | Unknown blueprint/artifact references, missing files |
| **Type** | Validation | Type mismatches, refinement constraint violations |
| **Semantic** | Validation | Duplicate names, circular dependencies, overlapping extendables |

---

## Message Format

All errors follow this structure:

```
<Category> Error in <file>:<line>

  <source context with pointer>

  <description>

  Defined in: <origin location>  (if applicable)

  Hint: <suggestion>             (if available)
```

---

## Example

```
Type Error in expectations/checkout.caffeine:15

  * "homepage_lcp" extends [_defaults]:
    Provides { threshold: 150.0 }
                          ^^^^^

  Refinement constraint violated:
    Expected: Float in range (0.0 .. 100.0)
    Got: 150.0

  Defined in blueprint "lcp_of_views" at blueprints.caffeine:23

  Hint: SLO thresholds are percentages between 0 and 100.
```
