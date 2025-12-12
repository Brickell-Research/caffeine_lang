# Todos

p0
* ensure all the AI code is good code
  * cql
  * middle end
  * generation

p1
* these error messages are not really consistently helpful

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
* this test pattern
* at the beginning, it was possible to successfullly compile a lot of code that wouldn't actually be "terraform apply"-able. How to make the compiler more helpful?
* so part of v2 was surfacing more to the user for configurations, beauty of debugging against the query vs. against the core compiler code was so sweet
* using internals?
* and we're live in the browser!

------------

## Notes

* no check for dupe dict keys, just overrides and technically illegal json per rfc/standard
* plan to support `Optional` type, but not yeto

-------------

## Learnings

* types over tuples
