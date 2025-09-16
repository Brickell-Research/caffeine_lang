# Phase 1

**Input:** Frontend YAML files
**Output:** Unresolved IR objects

Phase 1 consists of parsing the frontend YAML files into a intermediate representation (IR) objects as best as possible. Why as best as possible? Well, we are not always able to full resolve symbolic references (i.e. sli_types to services) and thus for some we don't return the IR proper, but an unresolved version.

This step is fairly straightfoward. Errors here surface when we're missing basic, expected fields. Due to the weak typing of YAML, there's not a ton we can say in terms of correctness here except that all labeled references between objects are valid.
