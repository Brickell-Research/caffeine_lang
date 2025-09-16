# caffeine

[![Test](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test.yml/badge.svg)](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?style=for-the-badge&logo=gleam&logoColor=black)](https://gleam.run/)

<div align="center">
<img src="images/caffeine_icon.png" alt="Caffeine Icon" width="250" height="250">
</div>

Caffeine is a compiler for generating reliability artifacts from service expectation definitions.

***

## Installation

TBD - we reccommend using within a CICD pipeline.

***

## Usage

### basic_types

**Definition:** basic mappings of `attribute_name` to `attribute_type` to be leveraged within specifications.

**Example:**
```gleam
basic_types:
  - attribute_name: "service_name"
    attribute_type: String
  - attribute_name: "environment"
    attribute_type: String
  - attribute_name: "requests_valid"
    attribute_type: Boolean
```

Valid types:
```
String | Integer | Decimal | Boolean | List(VALID_TYPE)
```

**Note**: technically, `List` is a recursive type that may recurse indefinitely. We don't recommend using this behavior in practice.

### query_template_types

**Definition:** a type of query template specification

**Example:**
```gleam
query_template_types:
  - name: "good_over_bad"
    specification_of_query_templates: ["numerator_query", "denominator_query"]
```

The specification_of_query_templates values map to `basic_types`.

### sli_types

**Definition:** a type of SLI specification that references a query template type and specifies the template variables to be used.

**Example:**
```gleam
sli_types:
  - name: "http_status_code"
    query_template_type: "good_over_bad"
    typed_instatiation_of_query_templates:
      numerator_query: "SOME_QUERY"
      denominator_query: "ANOTHER_QUERY"
    specification_of_query_templatized_variables: ["acceptable_status_codes"]
```

The specification_of_query_templatized_variables values map to `basic_types` while the typed_instatiation_of_query_templates values map to the `query_template_types`'s specification_of_query_templates values.


#### typed_instatiation_of_query_templates

During compilation, we take the templatized query templates and replace the template variables with the values from the typed_instatiation_of_query_templates. Within the typed_instatiation_of_query_templates queries, we specify template variables by prefixing and suffixing the variable name with `$$`. 

As an example, consider the following query:
```
SELECT COUNT(*) FROM $$service_name$$ WHERE $$environment$$ = 'production' AND $$requests_valid$$ = true
```

Thus, our `specification_of_query_templatized_variables` would be:
```gleam
specification_of_query_templatized_variables: ["service_name", "environment", "requests_valid"]
```

So, for a given SLO that leverages this query template instantiation, we'd take the typed instantiations of the query template variables and replace the template variables in the query template with the values from the typed instantiations:

```
SLO's typed_instatiation_of_query_templatized_variables:
* service_name --> "reliable_service"
* environment --> "production"
* requests_valid --> true

Resulting query:
```
SELECT COUNT(*) FROM reliable_service WHERE production = 'production' AND true = true
```

**Note**: we type check the typed_instatiation_of_query_templatized_variables values against the specification_of_query_templatized_variables values to ensure that the types match as part of compilation.

### services

**Definition:** a service is a named entity that supports a set of SLI types. While this may seem extraneous, it's a layer of explicitness that allows us to sanity check that the SLI types we support make sense for the service (i.e. don't support http request latency for a database service).

**Example:**
```gleam
services:
  - name: "reliable_service"
    supported_sli_types: ["http_status_code"]
```

The supported_sli_types values map to `sli_types`.

### slos

**Definition:** an SLO is an instantiation of an SLI Type with a threshod that serves as the stakeholder's expectation, calculated over a window of time.

**Example:**
```gleam
slos:
  - threshold: 99.5
    sli_type: "http_status_code"
    service_name: "reliable_service"
    window_in_days: 30
    typed_instatiation_of_query_templatized_variables:
      acceptable_status_codes: "[200, 201]"
```

The threshold value is a float from 0.0 to 100.0, the sli_type value maps to `sli_types`, the service_name value maps to `services`, the window_in_days value is an integer, and the typed_instatiation_of_query_templatized_variables value maps to the `sli_types`'s specification_of_query_templatized_variables.

### teams

**Definition:** a team is a named entity that owns a set of SLOs.

**Example:**
```gleam
teams:
  - name: "platform"
    slos: ["http_status_code"]
```

The slos values map to `slos`.

***

## Architecture & RFCs

For detailed architectural decisions and design proposals, see our [RFCs directory](rfcs/):

- [RFC 001: Extensible Architecture](rfcs/001_Extensible_Architecture.md) - Core architectural principles and design patterns
***

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

