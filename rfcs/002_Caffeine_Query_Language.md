# RFC 002: Caffeine Query Language

**Owner:** **Rob Durst**

**Status:** _implementation in progress_

**Date:** September 21, 2025

***

## Overview

CQL is a very simple arithmetic language that is used to express SLIs. We expect it to grow over time, but for it to never be Turing complete.

The following operators are supported:

- `/`           : Division
- `*`           : Multiplication
- `+`           : Addition
- `-`           : Subtraction
- `(` and `)`   : Parentheses

### Grammar

```
CQL_QUERY  ::= EXP
EXP        ::= ADD
ADD        ::= MUL (('+' | '-') MUL)*
MUL        ::= PRIMARY (('*' | '/') PRIMARY)*
PRIMARY    ::= WORD | '(' EXP ')'
WORD       ::= [A-Za-z_]+
```

### Query Primitives

While I've already placed a fairly rigid constraint on CQL by saying it's never going to be Turing complete, I'll further constrain by saying it must map to a _query primitive_. A query primitive is:

```
A query form or structure that comes shipped with caffeine; a sort of standard library for queries. 
```

For example, the first primitive we will support is `good and valid over total`. We _map_ to this by ensuring our query reduces to a numerator over a denominator.

## Phase to Phase

**(1): Parsing**

In this step, we parse the CQL query into its parse tree.

Input:
```
(A + B) / C
```

Output:
```gleam
let query  =   CQL_QUERY
                        └─ EXP
                           └─ ADD
                              └─ MUL
                                 ├─ PRIMARY
                                 │  └─ "(" EXP ")"
                                 │     └─ ADD
                                 │        ├─ MUL
                                 │        │  └─ PRIMARY
                                 │        │     └─ WORD("A")
                                 │        ├─ "+"
                                 │        └─ MUL
                                 │           └─ PRIMARY
                                 │              └─ WORD("B")
                                 ├─ "/"
                                 └─ PRIMARY
                                    └─ WORD("C")

UnresolvedQueryTemplateType(
  ...
  query: query
  ...
)
```

**(2): Linking**

Linking in the caffeine compiler is mostly about resolving references between structures from different files. Since the query is all in one file, it isn't modified at all in this step (it's just moved from one object to another).

Input:
```gleam
UnresolvedQueryTemplateType(
  ...
  query: query
  ...
)
```

Output:
```gleam
QueryTemplateType(
  ...
  query:  query
  ...
)
```

**(3): Semantic Analysis**

Here we perform a series of checks including, but not limited to:
* ensuring the types of query values are compatible

We do not modify the parse tree. We simply traverse to ensure its validity.

Input:
```gleam
QueryTemplateType(
  ...
  query: query
  ...
)
```

Output:
```gleam
QueryTemplateType(
  ...
  query: query
  ...
)
```

**(4): Resolution**

In this step, we attempt to reduce our CQL query to a query primitive. Then we resolve the query template variables. The final result is fairly close to what the backend generator will use

Input:
```gleam
QueryTemplateType(
  ...
  query: query
  ...
)
```

Output:
```gleam
QueryTemplateType(
  ...
  query: QUERY_PRIMITIVE(
    numerator = "(SOME_QUERY_A + SOME_QUERY_B)"
    denominator = "SOME_QUERY_C""
  ...
)
```

**(5): Generation**

Given a query primitive, we generator reliability artifact(s).

Input:
```gleam
QueryTemplateType(
  ...
  query: QUERY_PRIMITIVE(
    numerator = "(SOME_QUERY_A + SOME_QUERY_B)"
    denominator = "SOME_QUERY_C""
  ...
```

Output:
```terraform
...
query {
  numerator: "(SOME_QUERY_A + SOME_QUERY_B)"
  denominator: "SOME_QUERY_C"
}
```

## A Full Example

### Specification

**basic_types.yaml**
```yaml
basic_types:
  - attribute_name: some_value
    attribute_type: String
```

**query_template_types.yaml**
```yaml
query_template_types:
  - name: "valid_over_total"
    query: "numerator / denominator"
    specification_of_query_templates: ["numerator", "denominator"]
```

**sli_types.yaml**
```yaml
types:
  - name: success_rate
    query_template: valid_over_total
    specification_of_query_templates:
      - name: numerator
        query: "good_requests"
      - name: denominator
        query: "total_requests"
```

### Compilation

**(1): Parsing**

We parse each of the YAML files into their respective parse trees.

**(2): Linking**

We resolve references between the files. For example, the `success_rate` SLI type references the `valid_over_total` query template.

**(3): Semantic Analysis**

We ensure that all references are valid and that the types are compatible.

**(4): Resolution**

We resolve the query template variables. For the `success_rate` SLI type, we would resolve the `numerator` and `denominator` variables to their respective queries.

**(5): Generation**

We generate the reliability artifacts based on the resolved query primitives.

***
