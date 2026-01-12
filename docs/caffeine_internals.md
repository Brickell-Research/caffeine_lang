# Caffeine Internals

This document describes how Caffeine DSL constructs translate to the underlying JSON format.

---

## Extendables Are Inlined

Extendables (`_name (Provides):` and `_name (Requires):`) are **Caffeine-only** syntactic sugar. They do not exist in JSON output. When compiling, the compiler inlines (copy-pastes) extendable values directly into each item that extends them.

**Caffeine:**
```caffeine
_defaults (Provides): { env: "production", window_in_days: 30 }

Expects for "api_availability"
  * "checkout_availability" extends [_defaults]:
    Provides { threshold: 99.95, status: true }
```

**Compiled JSON:**
```json
{
  "name": "checkout_availability",
  "blueprint_ref": "api_availability",
  "inputs": {
    "env": "production",
    "window_in_days": 30,
    "threshold": 99.95,
    "status": true
  }
}
```

The `_defaults` extendable disappears entirely—its fields are merged into the expectation's `inputs`.

---

## Merge Order

When an item extends multiple extendables, values are merged left-to-right. **Overlapping keys are a compile error** - the compiler will not silently override values.

```caffeine
_a (Provides): { x: 1, y: 2 }
_b (Provides): { y: 3, z: 4 }

Expects for "some_blueprint"
  * "example" extends [_a, _b]:    # ERROR: 'y' defined in both _a and _b
    Provides { z: 5 }
```

To fix, remove the overlap from one extendable or don't extend both.

**Valid example:**

```caffeine
_a (Provides): { x: 1 }
_b (Provides): { y: 2 }

Expects for "some_blueprint"
  * "example" extends [_a, _b]:
    Provides { z: 3 }
```

**Result:** `{ x: 1, y: 2, z: 3 }`

The item's own `Provides` can define keys that don't exist in any extendable, but cannot override extendable keys either.

---

## Template Variables Are Translated

Template variable syntax in Caffeine is translated to the underlying JSON format:

| Caffeine | JSON |
|----------|------|
| `${var}` | `$$var$$` |
| `${var->attr}` | `$$var->attr$$` |
| `${var->attr.not}` | `$$var->attr:not$$` |

**Example:**

```caffeine
"sum:requests{${env->env}, ${status->status.not}}"
```

**Compiled JSON:**
```json
"sum:requests{$$env->env$$, $$status->status:not$$}"
```

---

## Comments Are Discarded

Comments (`# ...`) are for human readability only and are not preserved in JSON output.
