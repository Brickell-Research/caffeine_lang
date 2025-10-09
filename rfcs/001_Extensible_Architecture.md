# RFC 001: Extensible Architecture

**Owner:** **Rob Durst**

**Status:** _implementation in progress_

**Date:** September 10, 2025

***

## Overview

Fundamentally, `ez-slo` was a pipeline for the generation of `reliability artifacts` from SLO `specifications`. It differs from [OpenSLO](https://github.com/OpenSLO/OpenSLO) in that we seek a higher level of abstraction by default, lowering the barrier for entry and simultaneously improving consumability of configuration specifications through opinionated defaults following in the steps of the [Rails Doctrine's](https://rubyonrails.org/doctrine) _convention over configuration_. As originally written, the `yaml` specifications accomplished our goal, being a simple specification that autogenerates Datadog SLOs and a dashboard encompassing all these artifacts. **We do NOT seek to propose breaking changes to this format**. Instead we seek to redesign the internals in order to promote a more extensible and flexible architecture to support greater org wide adoption. Specifically, we aim to accomplish:

* clearer separation and isolation of compilation phases
* type adoption from the ground up
* move `slo type`, `service`, and `team` configuration to the frontend for better visibility and end-user malleability

Fundamentally we're writing a compiler here and we need to better structure this as such.

### A Cleaner Pipeline

As this is a compiler, we'll leverage a typical multi-phase design.

* **Phase 1 (Parsing)**: Parse YAML
  * validate format
  * translate to Unresolved Intermediate Representation
* **Phase 2 (Linking)**: Link specifications and instantiations
  * resolve symbolic references
  * produce fully resolved Organization IR
* **Phase 3 (Semantic Analysis)**: Type checking and semantic analysis
  * validate IR objects
  * ensure correctness
* **Phase 4 (Resolution)**: Resolve SLO queries
  * instantiate query templates with filters
  * produce optimized resolved SLOs
* **Phase 5 (Code Generation)**: Backend reliability artifact generation (i.e. Datadog SLOs, Terraform)

#### Intermediate Representation Language

```haskell
-- Top Level --
struct Organization {
  teams:               List<Team>
  service_definitions: List<Service>
}

-- Mid Level --
struct Team {
  name: String
  slos: List<Slo>
}

struct Service {
  name:              String
  supported_sli_types: List<SliType>
}

-- Low Level --
struct Slo {
  typed_instatiation_of_query_templatized_variables: TypedInstantiationOfQueryTemplates
  threshold:      Float
  sli_type:       String
  service_name:   String
  window_in_days: Int
}

struct SliType {
  name:                                            String
  query_template_type:                             QueryTemplateType
  typed_instatiation_of_query_templates:           TypedInstantiationOfQueryTemplates
  specification_of_query_templatized_variables:    SpecificationOfQueryTemplates
}

struct QueryTemplateType {
  specification_of_query_templates: SpecificationOfQueryTemplates
  name:                             String
  query:                            ExpContainer
}

struct BasicType {
  attribute_name: String
  attribute_type: AcceptedTypes
}

-- Type Aliases --
type SpecificationOfQueryTemplates = List<BasicType>

-- Core Level --
enum AcceptedTypes = Boolean | Decimal | Integer | String | List<AcceptedTypes>
```

#### Full Example

On the frontend a user defines the SLO(s) in YAML. We'll continue leveraging the directory structure to specify the team name and
the service.

`platform/reliable_service.yaml`

```yaml
slos:
  - sli_type: "success_rate"
    typed_instatiation_of_query_templatized_variables:
      "graphql_operation_name": "createappointment"
      "environment": "production"
    threshold: 99.9
    window_in_days: 7
```

Furthermore, within the `specifications/` directory we'd also have the following configuration files:

`specifications/basic_types.yaml`

```yaml
basic_types:
  - attribute_name: graphql_operation_name
    attribute_type: String
  - attribute_name: environment
    attribute_type: String
```

`specifications/sli_types.yaml`

```yaml
types:
  - name: success_rate
    query_template_type: valid_over_total
    typed_instatiation_of_query_templates:
      numerator: "sum:rotom.graphql.hits_and_errors{env:$$environment$$, graphql.operation_name:$$graphql_operation_name$$, status:info}.as_count()"
      denominator: "sum:rotom.graphql.hits_and_errors{env:$$environment$$, graphql.operation_name:$$graphql_operation_name$$}.as_count()"
    specification_of_query_templatized_variables:
      - graphql_operation_name
      - environment
```

`specifications/services.yaml`

```yaml
services:
  - name: reliable_service
    sli_types:
      - success_rate
```

From this we have the following IR:

`intermediate representation`
```ruby
## Instantiations
# An SLO
reliable_service_success_rate = Slo {
  typed_instatiation_of_query_templatized_variables: { graphql_operation_name: "createappointment", environment: "production" },
  threshold:      99.9,
  sli_type:       "success_rate",
  service_name:   "reliable_service",
  window_in_days: 7
}
# A team which owns SLOs and implicitly is a "collective" owner of a system
platform_team = Team {
  name: "platform",
  slos: [reliable_service_success_rate],
}

## Highest level view of system
# An org
org = Organization {
  teams: [platform_team],
  service_definitions: [reliable_service]
}
```

After type checking this, we'd then go on to generate whatever `reliability artifacts` the user desires.


### Gleam

We will be leveraging Gleam from the beginning to get strong static type checking and functional programming guarantees. Gleam provides type safety without runtime overhead, immutability by default, and excellent error messages - all critical for building a reliable compiler.

### Frontend User Configuration

Today relevant configurations are hidden from the user and shipped as part of the gem itself. This is not only less extensible, but a layer of abstraction we don't desire - while the average folks may not need to know the details of sli types, folks will and so having these live next to slo specifications makes more sense than within a totally separate repository. Furthermore, config changes will no longer require gem releases.

***