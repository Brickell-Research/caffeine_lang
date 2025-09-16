# Phase 4

**Input:** Fully resolved IR objects (top level Organization object)
**Output:** Optimized and resolved IR objects (list of SLOs)

Once we have our intermediate representation and it's full validated (phase 3), we have some further processing to do to generate the target artifacts for whatever the user has requested. In modern, and more complex compilers, this is where we'd perform optimizations. While optimizations might not quite make sense here, we do need to resolve the queries for each SLO by instantiating the query template with the appropriate filters.

For example, consider the following query filter:

```yaml
- attribute_name: number_of_users
  attribute_type: Integer
  required: true
- attribute_name: environment
  attribute_type: String
  required: true
- attribute_name: numerator_query
  attribute_type: String
  required: true
- attribute_name: denominator_query
  attribute_type: String
  required: true
```

And the following query template type:

```yaml
- name: good_over_bad
  specification_of_query_templates:
    - environment
    - number_of_users
```

And the following SLI Type:

```yaml
- name: error_rate
  query_template_type: good_over_bad
  specification_of_query_templatized_variables: [ environment, number_of_users ]
  typed_instatiation_of_query_templates:
    - numerator_query: "sum:service:errors{environment=$environment, minimum_users=$number_of_users}",
    - denominator_query: "sum:service:requests{environment=$environment, minimum_users=$number_of_users}",
```

And the following SLOs:

```yaml
- name: production_success_rate
  sli_type: error_rate
  threshold: 99.5
  typed_instatiation_of_query_templatized_variables:
    - number_of_users: 1000
    - environment: "production"
- name: staging_success_rate
  sli_type: error_rate
  threshold: 90.0
  typed_instatiation_of_query_templatized_variables:
    - number_of_users: 100
    - environment: "staging"
```

The final result would be:

```gleam
let resolved_slos = [
  ResolvedSlo {
    name: "production_success_rate",
    sli_type: "error_rate",
    threshold: 99.5,
    sli: ResolvedSli(
      query_template_type: "good_over_bad",
      metric_attributes: {
        numerator_query: "sum:service:errors{environment=\"production\", minimum_users=1000}",
        denominator_query: "sum:service:requests{environment=\"production\", minimum_users=1000}",
      },
    ),
  },
  ResolvedSlo {
    name: "staging_success_rate",
    sli_type: "error_rate",
    threshold: 90.0,
    sli: ResolvedSli(
      query_template_type: "good_over_bad",
      metric_attributes: {
        numerator_query: "sum:service:errors{environment=\"staging\", minimum_users=100}",
        denominator_query: "sum:service:requests{environment=\"staging\", minimum_users=100}",
      },
    ),
  }
]
```