# Todos

p0
* these error messages are not really consistently helpful
* tons of verbose, code i.e. mapping blueprint to artifact like 3x

p1
* function consistency and reuse between parsers: artifacts, blueprints, and expectations

-----------

First we get all the files:
* artifacts.yaml lives within the repo
* blueprints.yaml, only one file, they specify the location
* expectations is a directory with `org/team/service.yaml` structure

Then we parse:
1. get artifacts
2. pass artifacts to a parser and get blueprints, decoding and enforcing type
3. get blueprints from a parser and get expectations, decoding and enforcing type

With that we:
1. evaluate CQL

Finally we code gen:
1. Terraform

-----------

## Blog Post

* why extracted in yay is shit compared to json's decode
* love sets!

------------

## Notes

* no check for dupe dict keys, just overrides and technically illegal json per rfc/standard
* plan to support `Optional` type, but not yet
