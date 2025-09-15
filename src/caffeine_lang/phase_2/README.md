# Phase 2

**Input:** IR objects (resolved or unresolved)
**Output:** Fully resolved IR objects (top level Organization object)

Here we perform the linking of specifications (services, sli_types, sli_filters), instantiations (teams and slos), and then return a fully resolved top level Organization object.

## Specification Linking

Since specifications are defined across each type's separate YAML files, we need to perform linking to resolve symbolically referenced objects. Specifically, we need to link sli_filters to sli_types and sli_types to services. Consider the following:


```yaml
sli_filters.yaml

sli_filters:
  - name: http_status_code
    attribute_name: http_status_code
  - name: http_method
    attribute_name: http_method
```

```yaml
sli_types.yaml

sli_types:
  - name: http
    filters:
      - name: http_status_code
        query_template: "http_status_code:{{http_status_code}}"
```

```yaml
services.yaml

services:
  - name: my_service
    sli_types:
      - http
```

In this example, we need to resolve the `http` sli_types's `filters` and then the `my_service` service's `sli_types`.

**Note:** within the linking logic, we are able to ensure that each symbollical resolution works; that is, we can ensure that the `http` sli_type is able to resolve to a valid sli_type and that the `http` sli_type is able to resolve to a valid service. If either of these resolutions fail, we return an error.

## Instantiation Linking

Instantiation linking _does not_ require any symbolical resolution, as the instantiations are defined in a flat structure. Instead, here we aggregate all SLOs for a single team into a single team object since each team, unique due to directory structure, can have multiple SLOs (one file per service per team).

Consider the following:

```yaml
my_team/
  my_service/
    my_slo.yaml
    my_other_slo.yaml
```

In this example, we need to aggregate the `my_slo.yaml` and `my_other_slo.yaml` files into a single team object.

## Organization

The final step is to combine the linked specifications and instantiations into a single Organization object. This is a simple matter of combining the linked specifications and instantiations into a single Organization object. At this point we're able to return a fully resolved Organization object.

The astute reader will note that this resolved organization may be far from valid - for example, it may contain invalid filters within an SLO instantiation. We handle this in the next phase.
