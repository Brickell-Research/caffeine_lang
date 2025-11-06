# caffeine

[![Caffeine Language Test](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test_caffeine.yml/badge.svg)](https://github.com/Brickell-Research/caffeine_lang/actions/workflows/test_caffeine.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://www.gnu.org/licenses/gpl-3.0)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?style=for-the-badge&logo=gleam&logoColor=black)](https://gleam.run/)

<div align="center">
<img src="images/temp_caffeine_icon.png" alt="Caffeine Icon" width="250" height="250">
</div>

Caffeine is a compiler for generating reliability artifacts from service expectation definitions.

***

## Installation

**We recommend using within a CICD pipeline.**

Within a GitHub Actions workflow, you can use the following action:
```bash
- name: Caffeine Language GitHub Action
  uses: Brickell-Research/caffeine_lang_github_action@vmain
```

[See the action in the Github Actions Marketplace](https://github.com/marketplace/actions/caffeine-language-action).

***

## Architecture & RFCs

For detailed architectural decisions and design proposals, see our [RFCs directory](rfcs/):

- [RFC 001: Extensible Architecture](rfcs/001_Extensible_Architecture.md) - Core architectural principles and design patterns
- [RFC 002: Caffeine Query Language](rfcs/002_Caffeine_Query_Language.md) - The Caffeine Query Language (CQL)
***

## Quick Start

Projects are structured as follows:

```
some_organization/
├── platform/
│   └── reliable_service.yaml
├── frontend/
│   └── unreliable_service.yaml
├── specifications/
    ├── basic_types.yaml
    ├── query_template_types.yaml
    ├── services.yaml
    └── sli_types.yaml
```

Here we have two _types_ of files, `instantiation` and `specification`. 

### Instantiation

**Instantiation**: define the SLO(s) for a service. Each service defines one or more SLOs in a `yaml` file with the name of the file being the name of the service and the parent directory being the name of the owning team. 

As an example, `platform/reliable_service.yaml`:
```yaml
slos:
  - sli_type: "http_requests_success_rate"
    typed_instatiation_of_query_templatized_variables:
      "peer_hostname": "api.google.com"
      "environment": "production"
      "http_status_codes": "[200, 201, 202, 204]"
    threshold: 99.0
    window_in_days: 90
```

Here `threshold` and `window_in_days` are always required, `sli_type` refers to an sli type from the specification and `typed_instatiation_of_query_templatized_variables` is a series of mappings between expected attributes for the sli type and their values.

### Specification

**Specification**: define the templates available for defining SLI(s).

There are four types of specifications to define.

**(1) basic types:** a mapping of attribute names to the expected type. These are names of expected parameters used by other parts of the specification. 

Example:
```yaml
basic_types:
  - attribute_name: peer_hostname
    attribute_type: String
  - attribute_name: environment
    attribute_type: String
  - attribute_name: http_status_codes
    attribute_type: List(Integer)
```


**(2) query template types:** a definition of a query template type. The query is a CQL expression and the specification of query templates is a list of basic type names that are expected to be used in the query.

Example:
```yaml
query_template_types:
  - name: "valid_over_total"
    specification_of_query_templates: ["peer_hostname", "environment"]
    query: "numerator / denominator"
```


**(3) services:** a mapping of service names to supported sli types.

Example:
```yaml
services:
  - name: reliable_service
    sli_types:
      - http_requests_success_rate
```

**(4) sli types:** a definition of an SLI type that combines a query template type with specific query instantiations and the required templatized variables.

Example:
```yaml
types:
  - name: http_requests_success_rate
    query_template_type: valid_over_total
    typed_instatiation_of_query_templates:
      numerator: "sum.http_requests.hits{peer.hostname:$$peer_hostname$$ AND env:$$environment$$ AND http.status_code IN $$http_status_codes$$}.as_count()"
      denominator: "sum.http_requests.hits{peer.hostname:$$peer_hostname$$ AND env:$$environment$$}.as_count()"
    specification_of_query_templatized_variables:
      - peer_hostname
      - environment
      - http_status_codes
```

Once all of this is defined, execute the compiler as follows:
```gleam
compiler.compile("some_organization/specifications", "some_organization", "some_output_dir")
```

***

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

