# Phase 2

**Input:** Unresolved IR objects
**Output:** Fully resolved IR objects (top level Organization object)

Here we perform the linking of specifications (services, sli_types, sli_filters), instantiations (teams and slos), and then return a fully resolved top level Organization object.

## Specification Linking

Since specifications are defined across each type's separate YAML files, we need to perform linking to resolve symbolically referenced objects. Specifically, we need to link sli_filters to sli_types and sli_types to services. Consider the following:


```yaml
# filters.yaml
filters:
  - attribute_name: team_name
    attribute_type: String
  - attribute_name: number_of_users
    attribute_type: Integer
  - attribute_name: accepted_status_codes
    attribute_type: List(String)
```

```yaml
# sli_types.yaml
types:
  - name: latency
    query_template_type: good_over_bad
    typed_instatiation_of_query_templates:
      - numerator_query: "SomeQuery"
      - denominator_query: "SomeOtherQuery"
    specification_of_query_templatized_variables:
      - team_name
      - accepted_status_codes
  - name: error_rate
    query_template_type: good_over_bad
    typed_instatiation_of_query_templates:
      - numerator_query: "SomeQuery"
      - denominator_query: "SomeOtherQuery"
    specification_of_query_templatized_variables:
      - number_of_users
```

```yaml
# services.yaml
services:
  - name: reliable_service
    sli_types:
      - latency
      - error_rate
  - name: unreliable_service
    sli_types:
      - error_rate
```

In this example, we need to resolve the `http` sli_types's `specification_of_query_templatized_variables` and then the `my_service` service's `sli_types`.

**Note:** within the linking logic, we are able to ensure that each symbolic resolution works; that is, we can ensure that the `http` sli_type is able to resolve to a valid sli_type and that the `http` sli_type is able to resolve to a valid service. If either of these resolutions fail, we return an error.

## Instantiation Linking

Instantiation linking _does not_ require any symbolic resolution, as the instantiations are defined in a flat structure. Instead, here we aggregate all SLOs for a single team into a single team object since each team, unique due to directory structure, can have multiple SLOs (one file per service per team).

Consider the following:

```yaml
# my_team/my_service/slos.yaml
slos:
  - sli_type: "http_status_code"
    typed_instatiation_of_query_templatized_variables:
      "acceptable_status_codes": "[200, 201]"
    threshold: 99.5
    window_in_days: 30
  - sli_type: "latency"
    typed_instatiation_of_query_templatized_variables:
      "team_name": "'platform'"
      "accepted_status_codes": "[200, 201]"
    threshold: 99.9
    window_in_days: 7
```

In this example, we need to aggregate the `my_slo.yaml` and `my_other_slo.yaml` files into a single team object.

## Organization

The final step is to combine the linked specifications and instantiations into a single Organization object. This is a simple matter of combining the linked specifications and instantiations into a single Organization object. At this point we're able to return a fully resolved Organization object.

The astute reader will note that this resolved organization may be far from valid - for example, it may contain improperly typed typed_instatiation_of_query_templatized_variables within an SLO instantiation. We handle this in the next phase.
