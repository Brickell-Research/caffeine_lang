# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Plan: Extract Vendor Codegen Boilerplate into generator_utils

## Context

All 4 vendor codegen modules (datadog, honeycomb, dynatrace, newrelic) duplicate identical boilerplate for `terraform_settings()`, `provider()`, `generate_terraform()`, and `generate_resources()`. Only the vendor-specific resource building (`ir_to_terraform_resource`) and a few helper functions are truly unique per vendor. This refactoring extracts shared patterns into `generator_utils.gle...

### Prompt 2

ok whats next?

### Prompt 3

yes commit this firsy

