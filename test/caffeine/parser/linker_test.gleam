import caffeine/intermediate_representation.{
  Integer, Service, SliFilter, SliType,
}
import caffeine/parser/linker
import caffeine/parser/specification

pub fn fetch_by_attribute_name_sli_filter_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]

  assert linker.fetch_by_attribute_name_sli_filter(xs, "a")
    == Ok(SliFilter(
      attribute_name: "a",
      attribute_type: Integer,
      required: True,
    ))

  assert linker.fetch_by_attribute_name_sli_filter(xs, "c")
    == Error("Attribute c not found")
}

pub fn fetch_by_name_sli_type_test() {
  let xs = [
    SliType(name: "a", filters: [], query_template: "some_query_template"),
    SliType(name: "b", filters: [], query_template: "some_other_query_template"),
  ]

  assert linker.fetch_by_name_sli_type(xs, "a")
    == Ok(SliType(name: "a", filters: [], query_template: "some_query_template"))

  assert linker.fetch_by_name_sli_type(xs, "c") == Error("SliType c not found")
}

pub fn sugar_pre_sugared_sli_type_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]

  assert linker.sugar_pre_sugared_sli_type(
      specification.SliTypePreSugared(
        name: "a",
        filters: ["a", "b"],
        query_template: "some_query_template",
      ),
      xs,
    )
    == Ok(SliType(name: "a", filters: xs, query_template: "some_query_template"))
}

pub fn sugar_pre_sugared_sli_type_error_test() {
  let xs = [
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True),
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False),
  ]

  assert linker.sugar_pre_sugared_sli_type(
      specification.SliTypePreSugared(
        name: "a",
        filters: ["a", "b", "c"],
        query_template: "some_query_template",
      ),
      xs,
    )
    == Error("Failed to link sli filters to sli type")
}

pub fn sugar_pre_sugared_service_test() {
  let xs = [
    SliType(name: "a", filters: [], query_template: "some_query_template"),
    SliType(name: "b", filters: [], query_template: "some_other_query_template"),
  ]

  assert linker.sugar_pre_sugared_service(
      specification.ServicePreSugared(name: "a", sli_types: ["a", "b"]),
      xs,
    )
    == Ok(Service(name: "a", supported_sli_types: xs))
}

pub fn sugar_pre_sugared_service_error_test() {
  let xs = [
    SliType(name: "a", filters: [], query_template: "some_query_template"),
    SliType(name: "b", filters: [], query_template: "some_other_query_template"),
  ]

  assert linker.sugar_pre_sugared_service(
      specification.ServicePreSugared(name: "a", sli_types: ["a", "b", "c"]),
      xs,
    )
    == Error("Failed to link sli types to service")
}

pub fn link_and_validate_specification_sub_parts_test() {
  let sli_filter_a =
    SliFilter(attribute_name: "a", attribute_type: Integer, required: True)
  let sli_filter_b =
    SliFilter(attribute_name: "b", attribute_type: Integer, required: False)

  let sli_filters = [
    sli_filter_a,
    sli_filter_b,
  ]

  let pre_sugared_sli_types = [
    specification.SliTypePreSugared(
      name: "sli_type_a",
      filters: ["a", "b"],
      query_template: "some_query_template",
    ),
    specification.SliTypePreSugared(
      name: "sli_type_b",
      filters: ["a"],
      query_template: "some_other_query_template",
    ),
  ]

  let pre_sugared_services = [
    specification.ServicePreSugared(name: "service_a", sli_types: [
      "sli_type_a",
      "sli_type_b",
    ]),
  ]

  let expected_sli_types = [
    SliType(
      name: "sli_type_a",
      filters: [sli_filter_a, sli_filter_b],
      query_template: "some_query_template",
    ),
    SliType(
      name: "sli_type_b",
      filters: [sli_filter_a],
      query_template: "some_other_query_template",
    ),
  ]

  let expected_services = [
    Service(name: "service_a", supported_sli_types: expected_sli_types),
  ]

  assert linker.link_and_validate_specification_sub_parts(
      pre_sugared_services,
      pre_sugared_sli_types,
      sli_filters,
    )
    == Ok(expected_services)
}
