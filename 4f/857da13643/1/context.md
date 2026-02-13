# Session Context

## User Prompts

### Prompt 1

Implement the following plan:

# Plan: Deduplicate Codegen Vendor Boilerplate (A + B + C)

## Context
The 4 vendor codegen modules (datadog, honeycomb, dynatrace, newrelic) repeat identical patterns for description building, SLO field extraction, and error construction. This plan extracts shared logic into `generator_utils.gleam`.

## Changes

### A. Move `build_description` to `generator_utils.gleam`

Honeycomb (191-208), Dynatrace (164-181), and NewRelic (361-378) have word-for-word identical ...

### Prompt 2

ok, can we now go back to our list?

### Prompt 3

lay out a plan for E

### Prompt 4

[Request interrupted by user for tool use]

