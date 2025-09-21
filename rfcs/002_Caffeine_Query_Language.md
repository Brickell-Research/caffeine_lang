# RFC 002: Caffeine Query Language

**Owner:** **Rob Durst**

**Status:** _implementation in progress_

**Date:** September 21, 2025

***

## Overview

### Problem

After an initial integration of caffeine within a cicd pipeline, it became clear that we were still baking in a critical aspect of service expectation declaration within the core compier logic: the ability to specify (and surface such specifications) how the queries themselves should be structured as an expression.

For example we may specify:

```
query_template_types:
  - name: "success_rate"
    specification_of_query_templates: ["numerator", "denominator"]

types:
  - name: success_rate
    query_template_type: valid_over_total
    typed_instatiation_of_query_templates:
      numerator: "some_query"
      denominator: "some_query"
```

Yet this gives no insight into how `numerator` nor `denominator` are used in the actual query.

### Solution

We introduce _Caffeine Query Langauge_ to enable specification of how SLIs should be structured as an expression; CQL is a very simple arithmetic language that is used to express SLIs. We expect it to grow over time, but for it to never be Turing complete.

The following operators are supported:

- `/`           : Division
- `*`           : Multiplication
- `+`           : Addition
- `-`           : Subtraction
- `(` and `)`   : Parentheses

#### Grammar

```
CQL_QUERY  ::= EXP
EXP        ::= ADD
ADD        ::= MUL (('+' | '-') MUL)*
MUL        ::= PRIMARY (('*' | '/') PRIMARY)*
PRIMARY    ::= WORD | '(' EXP ')'
WORD       ::= [A-Za-z_]+
```

#### Query Primitives

While I've already placed a fairly rigid constraint on CQL by saying it's never going to be Turing complete, I'll further constrain by saying it must map to a _query primitive_. A query primitive is:

```
A query form or structure that comes shipped with caffeine; a sort of standard library for queries. 
```

For example, the first primitive we will support is `good and valid over total`. We _map_ to this by ensuring our query reduces to a numerator over a denominator.

***
