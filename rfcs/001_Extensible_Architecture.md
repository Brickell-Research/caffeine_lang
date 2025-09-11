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

* **Step 1 (Lexical and Static Analysis)**: Parse YAML
  * validate format
  * translate to Intermediate Systems Representation Language
* **Step 2 (Type Checking and Sematic Analysis)**: Traverse IR
* **Step 3**: Backend Code Generation (i.e. Datadog SLOs)

#### Intermediate Representation Language

```haskell
-- Top Level --
struct Organization {
  known_teams:         List<Team>
  service_definitions: List<Service>
}

-- Mid Level --
struct Team {
  name: String
  slos: List<SLO>
}

struct Service {
  name:                 String
  supported_slos_types: List<SLOType>
}

-- Low Level --
struct SLO {
  filters:   Hash<String, Any>
  threshold: Decimal
  type:      SLOType
}

struct SLOType {
  filters:        List<SLIFilterSpecification>
  name:           String
  query_template: String
}

struct SLIFilter {
  attribute_name: String
  attribute_type: AcceptedType
  required:       Boolean
}

-- Core Level --
enum AcceptedType = Boolean | Decimal | Integer | List<AcceptedTypes> | String
```

#### Full Example

On the frontend a user defines the SLO(s) in YAML. We'll continue leveraging the directory structure to specify the team name and
the service.

`foobar_team/authentication.yaml`
```yaml
slos_groups:
  - name: "User Sign Ups"
    slos:
      - type: http_success_rate
        target: 99.9
        good_and_valid_status_codes:
          - "200"
          - "409"
```

Furthermore, within the directory of these specifications we'd also have the following configuration:
```ruby
## Specification of System
# SLI filters
good_requests_filter = SLIFilter {
  attribute_name: "good_and_valid_status_codes",
  attribute_type: List<Integer>,
  required:       true
}
view_filter = SLIFilter {
  attribute_name: "view",
  attribute_type: String,
  required:       true
}
http_method_filter = SLIFilter {
  attribute_name: "method",
  attribute_type: String,
  required:       true
}
```

From this we have the following IR:

`intermediate representation`
```ruby
## Instantiations
# An SLO
authentication_signup_success_rate = SLO {
  filters:   { good_and_valid_status_codes: [200, 401], view: "/v1/users/members", method: "post" },
  threshold: 99.9,
  type:      http_success_rate_type
}
# A team which owns SLOs and implicitly is a "collective" owner of a system
foobar_team = Team {
  name: "Foobar",
  slos: [authentication_signup_success_rate],
}

## Highest level view of system
# An org
org = Organization {
  known_teams: [foobar_team]
}
```

After type checking this, we'd then go on to generate whatever `reliability artifacts` the user desires.


### Typed Ruby

We will be leveraging this from the beginning to get a combination of static and runtime type checking. By doing this, we can attempt to end up in a state of stronger type guarantees (i.e. no `T.untyped`...). 

### Frontend User Configuration

Today relevant configurations are hidden from the user and shipped as part of the gem itself. This is not only less extensible, but a layer of abstraction we don't desire - while the average folks may not need to know the details of slo types, folks will and so having these live next to slo specifications makes more sense than within a totally separate repository. Furthermore, config changes will no longer require gem releases.

***