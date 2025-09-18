import caffeine_lang/phase_2/linker/organization/linker
import caffeine_lang/types/accepted_types.{Integer}
import caffeine_lang/types/ast.{
  BasicType, Organization, QueryTemplateType, Service, SliType, Team,
}
import caffeine_lang/types/generic_dictionary
import gleam/dict
import gleam/list
import gleam/result
import gleam/string

pub fn get_instantiation_yaml_files_test() {
  let actual = linker.get_instantiation_yaml_files("./test/artifacts")

  let expected_files = [
    "./test/artifacts/platform/less_reliable_service.yaml",
    "./test/artifacts/platform/reliable_service.yaml",
    "./test/artifacts/platform/reliable_service_invalid_sli_type_type.yaml",
    "./test/artifacts/platform/reliable_service_invalid_threshold_type.yaml",
    "./test/artifacts/platform/reliable_service_missing_filters.yaml",
    "./test/artifacts/platform/reliable_service_missing_sli_type.yaml",
    "./test/artifacts/platform/reliable_service_missing_slos.yaml",
    "./test/artifacts/platform/reliable_service_missing_threshold.yaml",
    "./test/artifacts/platform/simple_yaml_load_test.yaml",
  ]

  case actual {
    Ok(files) -> {
      assert list.sort(files, string.compare)
        == list.sort(expected_files, string.compare)
    }
    Error(_) -> panic as "Failed to read instantiation files"
  }
}

pub fn link_specification_and_instantiation_test() {
  let actual =
    linker.link_specification_and_instantiation(
      "./test/artifacts/some_organization/specifications",
      "./test/artifacts/some_organization",
    )

  let expected_slo_reliable_service =
    ast.Slo(
      threshold: 99.5,
      sli_type: "error_rate",
      service_name: "reliable_service",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.GenericDictionary(
        dict.from_list([
          #(
            "number_of_users",
            generic_dictionary.TypedValue("100", accepted_types.Integer),
          ),
        ]),
      ),
      window_in_days: 30,
    )

  let expected_slo_less_reliable_service =
    ast.Slo(
      threshold: 99.5,
      sli_type: "error_rate",
      service_name: "less_reliable_service",
      typed_instatiation_of_query_templatized_variables: generic_dictionary.GenericDictionary(
        dict.from_list([
          #(
            "number_of_users",
            generic_dictionary.TypedValue("100_000", accepted_types.Integer),
          ),
        ]),
      ),
      window_in_days: 30,
    )

  let expected_basic_type =
    BasicType(attribute_name: "number_of_users", attribute_type: Integer)

  let expected_query_template_type =
    QueryTemplateType(name: "good_over_bad", specification_of_query_templates: [
      expected_basic_type,
    ])

  let expected_typed_instatiation =
    generic_dictionary.from_string_dict(
      dict.from_list([
        #(
          "numerator_query",
          "max:(successful_requests from{service=\"frontend\", number_of_users=$$number_of_users$$})",
        ),
        #(
          "denominator_query",
          "max:(total_requests from{service=\"frontend\", number_of_users=$$number_of_users$$})",
        ),
      ]),
      dict.from_list([
        #("numerator_query", accepted_types.String),
        #("denominator_query", accepted_types.String),
      ]),
    )
    |> result.unwrap(generic_dictionary.new())

  let expected_sli_type =
    SliType(
      name: "error_rate",
      query_template_type: expected_query_template_type,
      typed_instatiation_of_query_templates: expected_typed_instatiation,
      specification_of_query_templatized_variables: [expected_basic_type],
    )

  let expected =
    Ok(
      Organization(
        service_definitions: [
          Service(name: "reliable_service", supported_sli_types: [
            expected_sli_type,
          ]),
          Service(name: "less_reliable_service", supported_sli_types: [
            expected_sli_type,
          ]),
        ],
        teams: [
          Team(name: "frontend", slos: [expected_slo_less_reliable_service]),
          Team(name: "platform", slos: [expected_slo_reliable_service]),
        ],
      ),
    )

  assert actual == expected
}
