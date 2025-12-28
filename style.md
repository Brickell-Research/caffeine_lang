# Code Style Guide

## Imports

1. Import types unqualified (direct import)
2. Use qualified imports for everything else

```gleam
import some_module.{type MyType}

pub fn example() -> MyType {
  some_module.some_function()
}
```

## Type System Architecture

1. Keep type-specific logic close to the type definition
2. Use dispatcher pattern in parent types to delegate to child type modules
3. Pass recursive functions as parameters to avoid circular dependencies

## Testing

1. One test function per method
2. Directory structure mirrors `src/`
3. Use comment headers to summarize test cases
4. Use `// ==== Subsection ====` dividers within comment headers
5. Use array-based tests with `test_helpers.array_based_test_executor_*`

```gleam
// ==== Add ====
// * ✅ adds two numbers
// * ✅ handles negatives
pub fn add_test() {
  [
    #(1, 2, 3),
    #(-1, 1, 0)
  ]
  |> test_helpers.array_based_test_executor_2(math.add)
}
```

## Visibility

Use `@internal` to mark `pub fn` that shouldn't be part of the stable API.

### When to Use

- **Testing exposure**: Functions that are `pub` so tests can verify them directly
- **Implementation helpers**: Functions called by public entry points but not meant for external use

### When NOT to Use

Use plain `fn` (not `pub fn`) for truly private helpers that don't need test access.

| Need | Syntax |
|------|--------|
| Private (same module) | `fn` |
| Public for tests only | `@internal pub fn` |
| Stable public API | `pub fn` |

## Comments

### Doc Comments (`///`)

- Required for all `pub` items (including `@internal`)
- Capitalize first word, end with period
- Keep concise (1-3 lines) unless complex behavior needs explanation

### Inline Comments (`//`)

- Use sparingly to explain "why", not "what"
- Capitalize as a sentence
- Format TODOs as: `// TODO: description`

### Test Comments

- Header: `// ==== function_name ====`
- Case list: `// * ✅ case description`
- Subsections: `// ==== Section Name ====`

## Function Design

- **Data-first**: Put the main data as the first argument to enable piping
- **Labelled arguments**: Use labels for clarity when functions have multiple parameters

## Error Handling

- **Use `Result`**: Not exceptions
- **Custom error types**: Prefer over `String` for detailed, type-safe error handling

## Use Sparingly

- **`panic` / `let assert`**: Avoid in library code
- **`use` expression**: Excessive use makes code unclear
- **External functions**: Prefer Gleam code where possible
- **Type aliases**: Prefer custom types for clarity and type safety

## Patterns

- **Pipe operator**: Primary composition method
- **Recursion over loops**: Use `list.map`, `list.fold`, or explicit recursion
- **Tail recursion**: Public wrapper calls private recursive function with accumulator
- **Smart constructors**: Use opaque types with validation functions to enforce invariants
