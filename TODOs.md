# Todos

* can we clean up the tests to make more concise?
* instead of artifacts.0.name for path for json, can we specify the name (assuming it parses)?
* general investigation and thoughts on error messages

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
